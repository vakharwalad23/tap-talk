import Foundation

// Manages a llama-server subprocess for local LLM inference.
// The server exposes an OpenAI-compatible HTTP API on localhost.
final class LlamaServerManager {
    static let shared = LlamaServerManager()

    private var process: Process?
    private var readyCheckTask: Task<Void, Never>?

    let port = 8899  // Avoid clash with common ports
    var baseURL: String { "http://127.0.0.1:\(port)" }

    private(set) var isRunning = false

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
        // Suppress server stdout/stderr
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError  = FileHandle.nullDevice

        try proc.run()
        process = proc
        isRunning = true

        // Wait for the server to accept connections (up to 30s)
        try await waitForReady()
    }

    func stop() {
        readyCheckTask?.cancel()
        readyCheckTask = nil
        process?.terminate()
        process = nil
        isRunning = false
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

    func isBinaryInstalled() -> Bool {
        FileManager.default.fileExists(atPath: binaryPath())
    }

    // Downloads and extracts llama-server binary if not present.
    func ensureBinaryAvailable() async throws -> String {
        let path = binaryPath()
        if FileManager.default.fileExists(atPath: path) { return path }
        try await downloadBinary(to: path)
        return path
    }

    func downloadBinary(
        to destination: String,
        onProgress: ((Double) -> Void)? = nil
    ) async throws {
        let releaseInfo = try await fetchLatestReleaseInfo()
        guard let assetURL = releaseInfo.arm64MacosURL else {
            throw LlamaServerError.binaryNotFound
        }

        let zipURL = URL(fileURLWithPath: destination + ".zip")
        try await downloadFile(from: assetURL, to: zipURL, onProgress: onProgress)
        try extractLlamaServer(from: zipURL, to: destination)
        try? FileManager.default.removeItem(at: zipURL)

        // Mark executable
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination)
    }

    private func downloadFile(from url: URL, to dest: URL, onProgress: ((Double) -> Void)?) async throws {
        let delegate = DownloadDelegate(onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let (localURL, response) = try await session.download(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LlamaServerError.downloadFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        // Remove existing dest if present, then move
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: localURL, to: dest)
    }

    private func extractLlamaServer(from zipURL: URL, to destination: String) throws {
        let extractDir = zipURL.deletingPathExtension().path
        try? FileManager.default.createDirectory(atPath: extractDir, withIntermediateDirectories: true)

        let result = Process()
        result.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        result.arguments = ["-o", zipURL.path, "*/llama-server", "-d", extractDir]
        result.standardOutput = FileHandle.nullDevice
        result.standardError  = FileHandle.nullDevice
        try result.run()
        result.waitUntilExit()

        // Find the extracted binary
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(atPath: extractDir)
        for item in items {
            let candidate = (extractDir as NSString).appendingPathComponent(item + "/llama-server")
            if fm.fileExists(atPath: candidate) {
                try fm.moveItem(atPath: candidate, toPath: destination)
                try? fm.removeItem(atPath: extractDir)
                return
            }
            // Flat layout
            let flat = (extractDir as NSString).appendingPathComponent("llama-server")
            if fm.fileExists(atPath: flat) {
                try fm.moveItem(atPath: flat, toPath: destination)
                try? fm.removeItem(atPath: extractDir)
                return
            }
        }
        throw LlamaServerError.binaryNotFound
    }

    // MARK: GitHub release lookup

    private struct ReleaseInfo {
        let arm64MacosURL: URL?
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

        let arm64Asset = assets.first { asset in
            guard let name = asset["name"] as? String else { return false }
            return name.hasSuffix(".zip") && name.contains("macos") && name.contains("arm64")
        }

        let assetURL = (arm64Asset?["browser_download_url"] as? String).flatMap(URL.init)
        return ReleaseInfo(arm64MacosURL: assetURL)
    }

    // MARK: Readiness check

    private func waitForReady() async throws {
        let url = URL(string: "\(baseURL)/health")!
        var attempts = 0
        while attempts < 60 {
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            if let _ = try? await URLSession.shared.data(from: url) {
                return
            }
            attempts += 1
        }
        throw LlamaServerError.startTimeout
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let onProgress: ((Double) -> Void)?
    init(onProgress: ((Double) -> Void)?) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}

enum LlamaServerError: LocalizedError {
    case binaryNotFound
    case downloadFailed(String)
    case startTimeout

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:   return "llama-server binary not found in archive"
        case .downloadFailed(let msg): return "Download failed: \(msg)"
        case .startTimeout:     return "llama-server did not start in time"
        }
    }
}
