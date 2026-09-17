import Foundation
import CryptoKit
import OrukeetCoreML

// TapTalk-side Orukeet engine. Owns download, sha256 verification, unzip, and the
// on-device .mlpackage to .mlmodelc compile; wraps OrukeetCoreML for load and
// transcribe. Batch only - Orukeet has no streaming variant, so live typing stays
// on Parakeet + EOU. Downloaded only on explicit user action from the catalog.
actor OrukeetEngine {
    // Our own downloader, so the URL is revision-pinned (unlike FluidAudio's hardcoded main).
    private static let downloadURLString =
        "https://huggingface.co/oruk/orukeet/resolve/coreml-taptalk-preview-20260915/coreml/orukeet-r3-coreml-greedy.zip"
    private static let expectedSHA256 =
        "beccdc6f18c4b10527a764f6e3ab12e3e11b969220c0cee175b3bb7eaa94290e"
    private static let components = ["Preprocessor", "Encoder", "Decoder", "JointDecisionv3"]
    private static let vocabFile = "parakeet_vocab.json"

    private var inner: OrukeetCoreML.OrukeetEngine?

    enum EngineError: LocalizedError {
        case notInstalled
        case checksumMismatch
        case bundleLayout
        case unzipFailed(Int32)
        var errorDescription: String? {
            switch self {
            case .notInstalled:      return "Orukeet model not installed - download it in Models"
            case .checksumMismatch:  return "Downloaded Orukeet model is corrupt - please retry"
            case .bundleLayout:      return "Orukeet download is missing expected model files"
            case .unzipFailed(let c): return "Could not unpack the Orukeet download (code \(c))"
            }
        }
    }

    // MARK: Paths

    private static func downloadURL() -> URL {
        guard let url = URL(string: downloadURLString) else {
            preconditionFailure("Orukeet download URL literal is malformed")
        }
        return url
    }
    private static func rootDir() -> URL {
        URL(fileURLWithPath: AppController.modelsDirectory())
            .appendingPathComponent("Orukeet", isDirectory: true)
    }
    static func compiledDir() -> URL { rootDir().appendingPathComponent("compiled", isDirectory: true) }
    private static func packagesDir() -> URL { rootDir().appendingPathComponent("packages", isDirectory: true) }
    private static func stampFile() -> URL { compiledDir().appendingPathComponent(".osbuild") }
    private static func currentOSStamp() -> String { ProcessInfo.processInfo.operatingSystemVersionString }

    // MARK: Install state

    nonisolated static func isDownloaded() -> Bool {
        let dir = packagesDir()
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.appendingPathComponent(vocabFile).path) else { return false }
        return components.allSatisfy {
            fm.fileExists(atPath: dir.appendingPathComponent("\($0).mlpackage").path)
        }
    }

    nonisolated static func isInstalled() -> Bool {
        let dir = compiledDir()
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.appendingPathComponent(vocabFile).path),
              components.allSatisfy({ fm.fileExists(atPath: dir.appendingPathComponent("\($0).mlmodelc").path) })
        else { return false }
        guard let saved = try? String(contentsOf: stampFile(), encoding: .utf8) else { return false }
        return saved == currentOSStamp()
    }

    // MARK: Install pipeline

    // Download + verify + unzip into packages/. Does NOT compile (the installer runs
    // compile() separately so it can show a distinct compiling phase).
    nonisolated static func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: rootDir(), withIntermediateDirectories: true)

        let tmpZip = rootDir().appendingPathComponent("greedy.zip.partial")
        try? fm.removeItem(at: tmpZip)
        do {
            try await ZipDownloader.download(from: downloadURL(), to: tmpZip, progress: progress)
            guard try sha256(of: tmpZip) == expectedSHA256 else { throw EngineError.checksumMismatch }

            let unzipTmp = rootDir().appendingPathComponent("unzip-tmp", isDirectory: true)
            try? fm.removeItem(at: unzipTmp)
            try fm.createDirectory(at: unzipTmp, withIntermediateDirectories: true)
            try unzip(tmpZip, to: unzipTmp)

            let bundleRoot = try locateBundleRoot(in: unzipTmp)
            let staged = packagesDir()
            try? fm.removeItem(at: staged)
            if bundleRoot == unzipTmp {
                try fm.moveItem(at: unzipTmp, to: staged)
            } else {
                try fm.moveItem(at: bundleRoot, to: staged)
                try? fm.removeItem(at: unzipTmp)
            }
            try? fm.removeItem(at: tmpZip)
        } catch {
            try? fm.removeItem(at: tmpZip)
            sweepOrphans()
            throw error
        }
    }

    // Compile packages/ to compiled/. compilePackages is not idempotent, so start clean.
    nonisolated static func compile() throws {
        let fm = FileManager.default
        try? fm.removeItem(at: compiledDir())
        try OrukeetLocalModels.compilePackages(from: packagesDir(), to: compiledDir())
        try currentOSStamp().write(to: stampFile(), atomically: true, encoding: .utf8)
    }

    // Recompile a stale or interrupted cache (e.g. after a macOS upgrade) without
    // re-downloading. Safe no-op if nothing to do. Call off the main thread.
    nonisolated static func reconcileCompiledCache() {
        guard isDownloaded(), !isInstalled() else { return }
        try? compile()
    }

    // Reclaim disk from an interrupted download WITHOUT destroying a complete, still-usable
    // package set (which reconcileCompiledCache can recompile after an OS upgrade). Only stray
    // temporaries and an incomplete packages dir are removed. Runs every launch, so it must
    // never delete a valid download just because the compiled cache is absent or OS-stale.
    nonisolated static func sweepOrphans() {
        let fm = FileManager.default
        try? fm.removeItem(at: rootDir().appendingPathComponent("greedy.zip.partial"))
        try? fm.removeItem(at: rootDir().appendingPathComponent("unzip-tmp"))
        guard !isDownloaded() else { return }   // complete package set present: keep everything
        try? fm.removeItem(at: packagesDir())
        if !isInstalled() { try? fm.removeItem(at: rootDir()) }
    }

    nonisolated static func delete() throws {
        let dir = rootDir()
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    // MARK: Load / transcribe

    func ensureLoaded() async throws {
        guard inner == nil else { return }
        guard Self.isInstalled() else { throw EngineError.notInstalled }
        let engine = OrukeetCoreML.OrukeetEngine(modelDirectory: Self.compiledDir())
        try await engine.ensureLoaded()
        inner = engine
    }

    func unload() async {
        await inner?.unload()
        inner = nil
    }

    struct Output {
        let text: String
        let processingMs: UInt64
    }

    func transcribe(samples: [Float]) async throws -> Output {
        try await ensureLoaded()
        guard let inner else { throw EngineError.notInstalled }
        let out = try await inner.transcribe(samples: samples)
        return Output(
            text: out.text,
            processingMs: UInt64(max(0, out.processingMs))
        )
    }

    // MARK: Helpers

    private nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func unzip(_ zip: URL, to dir: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, dir.path]
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw EngineError.unzipFailed(process.terminationStatus) }
    }

    // The zip may hold the components loose at the top level or inside one folder.
    private nonisolated static func locateBundleRoot(in dir: URL) throws -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.appendingPathComponent("Encoder.mlpackage").path) { return dir }
        let entries = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for entry in entries where entry.hasDirectoryPath {
            if fm.fileExists(atPath: entry.appendingPathComponent("Encoder.mlpackage").path) { return entry }
        }
        throw EngineError.bundleLayout
    }
}

// Streams a large file to disk with fractional progress. URLSession's byte-stream is
// per-byte and too slow for a ~467 MB asset, so use a download delegate. The continuation
// is lock-guarded and resumed exactly once, and Task cancellation cancels the transfer.
final class ZipDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?

    private init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }

    // Resume once; a second delegate callback (e.g. didComplete after didFinish) is a no-op.
    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(with: result)
    }

    static func download(from url: URL, to dest: URL,
                         progress: @escaping @Sendable (Double) -> Void) async throws {
        let delegate = ZipDownloader(progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: url)
        let tempURL = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
                delegate.lock.lock()
                delegate.continuation = cont
                delegate.lock.unlock()
                task.resume()
            }
        } onCancel: {
            task.cancel()   // surfaces as URLError.cancelled via didCompleteWithError
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tempURL, to: dest)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The temp file is deleted when this delegate returns, so hand back a copy.
        let holding = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".zip")
        do {
            try FileManager.default.moveItem(at: location, to: holding)
            finish(.success(holding))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }
}
