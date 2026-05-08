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

    private var idleTask: Task<Void, Never>?
    private static let idleTimeout: TimeInterval = 600

    // Activity counters guarded by activityLock — read by the idle task on a
    // separate cooperative thread, written by LLM client calls on transcribe tasks.
    private let activityLock = NSLock()
    private var inFlightRequests: Int = 0
    private var lastActivity: Date = Date()

    private var currentModelPath: String?

    private init() {}

    // Ensure the server is running for the given model path.
    // No-op if already running for the same model; restarts on model swap.
    func ensureRunning(modelPath: String) async throws {
        if isRunning, let proc = process, proc.isRunning, currentModelPath == modelPath {
            if await isServerReachable() { return }
        }
        try await start(modelPath: modelPath)
    }

    // TCP probe — proc.isRunning lies briefly after external SIGKILL/OOM, so
    // a fast connect attempt avoids hanging the next /health call for ~60s.
    private func isServerReachable() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let conn = NWConnection(
                host: "127.0.0.1",
                port: NWEndpoint.Port(integerLiteral: UInt16(self.port)),
                using: .tcp
            )
            var settled = false
            let queue = DispatchQueue.global(qos: .userInitiated)
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if !settled { settled = true; conn.cancel(); cont.resume(returning: true) }
                case .failed, .cancelled:
                    if !settled { settled = true; cont.resume(returning: false) }
                default: break
                }
            }
            conn.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 0.1) {
                if !settled { settled = true; conn.cancel(); cont.resume(returning: false) }
            }
        }
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
        currentModelPath = modelPath
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
        currentModelPath = nil
    }

    func markActivity() {
        activityLock.lock()
        lastActivity = Date()
        activityLock.unlock()
    }

    func beginRequest() {
        activityLock.lock()
        inFlightRequests += 1
        lastActivity = Date()
        activityLock.unlock()
    }

    func endRequest() {
        activityLock.lock()
        if inFlightRequests > 0 { inFlightRequests -= 1 }
        activityLock.unlock()
    }

    private func snapshotActivity() -> (inFlight: Int, lastActivity: Date) {
        activityLock.lock()
        defer { activityLock.unlock() }
        return (inFlightRequests, lastActivity)
    }

    private func startIdleMonitor() {
        idleTask?.cancel()
        markActivity()
        idleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if Task.isCancelled { return }
                guard let self = self else { return }
                let snap = self.snapshotActivity()
                if self.isRunning,
                   snap.inFlight == 0,
                   Date().timeIntervalSince(snap.lastActivity) > Self.idleTimeout {
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
    // Stages into a sibling dir then atomic-swaps so a killed tar can't leave a
    // half-populated bin dir that still passes isBinaryInstalled().
    private func extractLlamaArchive(archiveURL: URL, into destDir: String) throws {
        let staging = (destDir as NSString).appendingPathComponent(".staging")
        try? FileManager.default.removeItem(atPath: staging)
        try FileManager.default.createDirectory(atPath: staging, withIntermediateDirectories: true)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        proc.arguments = ["-xzf", archiveURL.path, "-C", staging, "--strip-components=1"]
        let errPipe = Pipe()
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError  = errPipe
        try proc.run()
        proc.waitUntilExit()

        if proc.terminationStatus != 0 {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            try? FileManager.default.removeItem(atPath: staging)
            throw LlamaServerError.downloadFailed("tar failed: \(err.prefix(200))")
        }

        let stagedBinary = (staging as NSString).appendingPathComponent("llama-server")
        guard FileManager.default.fileExists(atPath: stagedBinary) else {
            try? FileManager.default.removeItem(atPath: staging)
            throw LlamaServerError.binaryNotFound
        }

        try? FileManager.default.removeItem(atPath: destDir)
        try FileManager.default.moveItem(atPath: staging, toPath: destDir)
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
        guard let apiURL = URL(string: "https://api.github.com/repos/ggml-org/llama.cpp/releases/latest") else {
            throw LlamaServerError.downloadFailed("invalid GitHub API URL")
        }
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
        guard let url = URL(string: "\(baseURL)/health") else {
            throw LlamaServerError.startTimeout
        }
        var attempts = 0
        while attempts < 180 {
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            // llama-server returns 503 while loading the model — only treat 200 as ready.
            if let (_, response) = try? await URLSession.shared.data(from: url),
               let http = response as? HTTPURLResponse,
               http.statusCode == 200 {
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
