import Foundation
import Network

// Manages a llama-server subprocess for local LLM inference.
// The server exposes an OpenAI-compatible HTTP API on localhost.
final class LlamaServerManager {
    static let shared = LlamaServerManager()

    private var process: Process?
    private var readyCheckTask: Task<Void, Never>?
    private var logHandle: FileHandle?

    private static let portRange = 8899...8910
    private(set) var port = 8899
    var baseURL: String { "http://127.0.0.1:\(port)" }

    private(set) var isRunning = false

    private var lastActivity: Date = Date()
    private var idleTask: Task<Void, Never>?
    private static let idleTimeout: TimeInterval = 600

    private init() {}

    // Ensure the server is running for the given model path.
    // No-op if already running for the same model.
    func ensureRunning(modelPath: String) async throws {
        if isRunning, let proc = process, proc.isRunning { return }
        try await start(modelPath: modelPath)
    }

    func start(modelPath: String) async throws {
        stop()

        let binaryPath = try await ensureBinaryAvailable()

        guard let chosenPort = await selectAvailablePort() else {
            throw LlamaServerError.portUnavailable
        }
        self.port = chosenPort

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = [
            "--model", modelPath,
            "--host", "127.0.0.1",
            "--port", "\(port)",
            "--ctx-size", "2048",
            "--n-predict", "512",
            "--n-gpu-layers", "99",
            "--log-disable",
        ]

        // Capture stdout+stderr to a log file so failed model loads / crashes are diagnosable
        let logPath = (LlamaServerManager.logsDirectory() as NSString).appendingPathComponent("llama-server.log")
        FileManager.default.createFile(atPath: logPath, contents: nil)
        if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logPath)) {
            proc.standardOutput = handle
            proc.standardError  = handle
            self.logHandle = handle
        } else {
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError  = FileHandle.nullDevice
        }

        try proc.run()
        process = proc
        isRunning = true

        try await waitForReady()
        startIdleMonitor()
    }

    func stop() {
        idleTask?.cancel()
        idleTask = nil
        readyCheckTask?.cancel()
        readyCheckTask = nil
        try? logHandle?.close()
        logHandle = nil
        process?.terminate()
        process = nil
        isRunning = false
    }

    func markActivity() {
        lastActivity = Date()
    }

    private func startIdleMonitor() {
        idleTask?.cancel()
        lastActivity = Date()
        idleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if Task.isCancelled { return }
                guard let self = self else { return }
                if self.isRunning,
                   Date().timeIntervalSince(self.lastActivity) > Self.idleTimeout {
                    self.stop()
                    return
                }
            }
        }
    }

    // Probe ports by binding a short-lived NWListener; reuse the first that succeeds
    private func selectAvailablePort() async -> Int? {
        for p in Self.portRange {
            do {
                let listener = try NWListener(
                    using: .tcp,
                    on: NWEndpoint.Port(integerLiteral: UInt16(p))
                )
                listener.cancel()
                return p
            } catch {
                continue
            }
        }
        return nil
    }

    // MARK: Binary management

    func binaryPath() -> String {
        let dir = LlamaServerManager.binaryDirectory()
        return (dir as NSString).appendingPathComponent("llama-server")
    }

    private static func binaryDirectory() -> String {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return NSTemporaryDirectory()
        }
        let dir = appSupport.appendingPathComponent("talk.tap.app/bin").path
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func logsDirectory() -> String {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return NSTemporaryDirectory()
        }
        let dir = appSupport.appendingPathComponent("talk.tap.app/logs").path
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    func isBinaryInstalled() -> Bool {
        FileManager.default.fileExists(atPath: binaryPath())
    }

    // Wipes the entire bin directory (binary + bundled dylibs).
    func removeBinary() {
        stop()
        let dir = LlamaServerManager.binaryDirectory()
        try? FileManager.default.removeItem(atPath: dir)
    }

    // Downloads and extracts llama-server binary if not present.
    func ensureBinaryAvailable() async throws -> String {
        let path = binaryPath()
        if FileManager.default.fileExists(atPath: path) { return path }
        try await downloadBinary(to: path, onBytesProgress: nil)
        return path
    }

    func fetchBinaryAsset() async throws -> (url: URL, size: UInt64) {
        let info = try await fetchLatestReleaseInfo()
        guard let url = info.arm64MacosURL else {
            throw LlamaServerError.binaryNotFound
        }
        return (url, info.arm64MacosSize)
    }

    func downloadBinary(
        to destination: String,
        onBytesProgress: ((UInt64, UInt64) -> Void)? = nil,
        knownAsset: (url: URL, size: UInt64)? = nil
    ) async throws {
        let asset: (url: URL, size: UInt64)
        if let known = knownAsset {
            asset = known
        } else {
            asset = try await fetchBinaryAsset()
        }

        let archiveURL = URL(fileURLWithPath: destination + ".tar.gz")
        try await downloadFile(
            from: asset.url,
            to: archiveURL,
            expectedSize: asset.size,
            onBytesProgress: onBytesProgress
        )
        try extractLlamaArchive(archiveURL: archiveURL, into: (destination as NSString).deletingLastPathComponent)
        try? FileManager.default.removeItem(at: archiveURL)

        guard FileManager.default.fileExists(atPath: destination) else {
            throw LlamaServerError.binaryNotFound
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination)
        stripQuarantine(at: (destination as NSString).deletingLastPathComponent)
    }

    private func downloadFile(
        from url: URL,
        to dest: URL,
        expectedSize: UInt64,
        onBytesProgress: ((UInt64, UInt64) -> Void)?
    ) async throws {
        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LlamaServerError.downloadFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        let serverTotal = response.expectedContentLength
        let total: UInt64 = serverTotal > 0 ? UInt64(serverTotal) : expectedSize
        var received: UInt64 = 0

        try? FileManager.default.removeItem(at: dest)
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        let handle = try FileHandle(forWritingTo: dest)

        var chunk = Data(capacity: 262_144)
        for try await byte in asyncBytes {
            chunk.append(byte)
            if chunk.count >= 262_144 {
                try handle.write(contentsOf: chunk)
                received += UInt64(chunk.count)
                chunk.removeAll(keepingCapacity: true)
                onBytesProgress?(received, total)
            }
        }
        if !chunk.isEmpty {
            try handle.write(contentsOf: chunk)
            received += UInt64(chunk.count)
        }
        try handle.close()
        onBytesProgress?(received, max(total, received))
    }

    // Extracts the macos-arm64 release tarball into `destDir` flat (strips top-level
    // versioned dir). llama-server uses @rpath = @loader_path, so its dylibs must
    // live in the same directory as the binary.
    private func extractLlamaArchive(archiveURL: URL, into destDir: String) throws {
        try? FileManager.default.createDirectory(atPath: destDir, withIntermediateDirectories: true)

        // Earlier versions of this code created a stale `<destDir>/llama-server`
        // directory on extract failure. Clear it before extracting a real binary.
        let staleBinary = (destDir as NSString).appendingPathComponent("llama-server")
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: staleBinary, isDirectory: &isDir), isDir.boolValue {
            try? FileManager.default.removeItem(atPath: staleBinary)
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        proc.arguments = ["-xzf", archiveURL.path, "-C", destDir, "--strip-components=1"]
        let errPipe = Pipe()
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError  = errPipe
        try proc.run()
        proc.waitUntilExit()

        if proc.terminationStatus != 0 {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw LlamaServerError.downloadFailed("tar failed: \(err.prefix(200))")
        }
    }

    // Removes com.apple.quarantine xattr from every file under `dir`. Required so
    // Gatekeeper does not block dlopen of the bundled dylibs.
    private func stripQuarantine(at dir: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        proc.arguments = ["-rd", "com.apple.quarantine", dir]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError  = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
    }

    // MARK: GitHub release lookup

    private struct ReleaseInfo {
        let arm64MacosURL: URL?
        let arm64MacosSize: UInt64
    }

    private func fetchLatestReleaseInfo() async throws -> ReleaseInfo {
        let apiURL = URL(string: "https://api.github.com/repos/ggml-org/llama.cpp/releases/latest")!
        var req = URLRequest(url: apiURL, timeoutInterval: 15)
        req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = json["assets"] as? [[String: Any]] else {
            throw LlamaServerError.downloadFailed("invalid GitHub API response")
        }

        // Match the plain macOS arm64 tarball. Skip the kleidiai variant (CPU-only
        // optimisations; we want Metal).
        let arm64Asset = assets.first { asset in
            guard let name = asset["name"] as? String else { return false }
            return name.hasSuffix(".tar.gz")
                && name.contains("macos")
                && name.contains("arm64")
                && !name.contains("kleidiai")
        }

        let assetURL = (arm64Asset?["browser_download_url"] as? String).flatMap(URL.init)
        let assetSize: UInt64 = {
            if let n = arm64Asset?["size"] as? UInt64 { return n }
            if let n = arm64Asset?["size"] as? Int64, n > 0 { return UInt64(n) }
            if let n = arm64Asset?["size"] as? Int, n > 0 { return UInt64(n) }
            if let n = arm64Asset?["size"] as? NSNumber { return n.uint64Value }
            return 0
        }()
        return ReleaseInfo(arm64MacosURL: assetURL, arm64MacosSize: assetSize)
    }

    // MARK: Readiness check

    private func waitForReady() async throws {
        let url = URL(string: "\(baseURL)/health")!
        var attempts = 0
        while attempts < 180 {
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            if let _ = try? await URLSession.shared.data(from: url) {
                return
            }
            attempts += 1
        }
        throw LlamaServerError.startTimeout
    }
}


enum LlamaServerError: LocalizedError {
    case binaryNotFound
    case downloadFailed(String)
    case startTimeout
    case portUnavailable

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:   return "llama-server binary not found in archive"
        case .downloadFailed(let msg): return "Download failed: \(msg)"
        case .startTimeout:     return "llama-server did not start in time"
        case .portUnavailable:  return "No free local port in 8899-8910"
        }
    }
}
