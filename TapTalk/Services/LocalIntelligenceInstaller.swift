import Foundation

@MainActor
final class LocalIntelligenceInstaller: ObservableObject {
    static let shared = LocalIntelligenceInstaller()

    enum Status: Equatable {
        case idle
        case preparing
        case downloading(fraction: Double, bytesDone: UInt64, bytesTotal: UInt64)
        case ready
        case failed(String)
    }

    static let modelId = "qwen2.5-1.5b"
    // Refined by Content-Length / Rust callback once the download starts
    static let estimatedModelBytes: UInt64 = 1_034_222_080

    @Published private(set) var status: Status = .idle

    private var task: Task<Void, Never>?
    private var modelDone: UInt64 = 0
    private var modelTotal: UInt64 = 0
    private var binaryDone: UInt64 = 0
    private var binaryTotal: UInt64 = 0

    private init() {
        if isFullyInstalled() { status = .ready }
    }

    func isFullyInstalled() -> Bool {
        AppController.shared.manager.isLlmInstalled(modelId: Self.modelId)
            && LlamaServerManager.shared.isBinaryInstalled()
    }

    // Rough estimate of bytes still to download given current disk state.
    // Returns 0 if everything is installed.
    func pendingDownloadBytes() -> UInt64 {
        var total: UInt64 = 0
        if !AppController.shared.manager.isLlmInstalled(modelId: Self.modelId) {
            total += Self.estimatedModelBytes
        }
        if !LlamaServerManager.shared.isBinaryInstalled() {
            // GitHub release size unknown until queried; ~8-10 MB tarball
            total += 10 * 1_048_576
        }
        return total
    }

    func reconcileFromDisk() {
        switch status {
        case .idle, .ready:
            status = isFullyInstalled() ? .ready : .idle
        default:
            break
        }
    }

    func install() {
        switch status {
        case .preparing, .downloading:
            return
        default:
            break
        }
        if isFullyInstalled() { status = .ready; return }

        modelDone = 0; modelTotal = 0
        binaryDone = 0; binaryTotal = 0
        status = .preparing

        task?.cancel()
        task = Task { [weak self] in
            await self?.runInstall()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        LlamaServerManager.shared.stop()
        modelDone = 0; modelTotal = 0
        binaryDone = 0; binaryTotal = 0
        status = isFullyInstalled() ? .ready : .idle
    }

    func remove() {
        task?.cancel()
        task = nil
        try? AppController.shared.manager.deleteLlm(modelId: Self.modelId)
        LlamaServerManager.shared.removeBinary()
        modelDone = 0; modelTotal = 0
        binaryDone = 0; binaryTotal = 0
        status = .idle
    }

    func retry() { install() }

    private func runInstall() async {
        let needsModel = !AppController.shared.manager.isLlmInstalled(modelId: Self.modelId)
        let needsBinary = !LlamaServerManager.shared.isBinaryInstalled()

        guard needsModel || needsBinary else {
            status = .ready
            return
        }

        do {
            var binaryAsset: (url: URL, size: UInt64)? = nil
            if needsBinary {
                let asset = try await LlamaServerManager.shared.fetchBinaryAsset()
                binaryAsset = asset
                binaryTotal = asset.size
            }
            if needsModel {
                modelTotal = Self.estimatedModelBytes
            }
            recompute()

            try await withThrowingTaskGroup(of: Void.self) { group in
                if needsModel {
                    group.addTask { [weak self] in
                        try await self?.downloadModel()
                    }
                }
                if needsBinary, let asset = binaryAsset {
                    group.addTask { [weak self] in
                        try await self?.downloadBinary(asset: asset)
                    }
                }
                while try await group.next() != nil {}
            }

            if Task.isCancelled { status = .idle; return }

            // Verify any time the file is on disk - Rust's existence check can't detect a truncated GGUF from a cancelled prior run
            if AppController.shared.manager.isLlmInstalled(modelId: Self.modelId) {
                try verifyModelIntegrity()
            }

            status = .ready
        } catch is CancellationError {
            status = .idle
        } catch {
            LlamaServerManager.shared.stop()
            status = .failed(error.localizedDescription)
        }
    }

    // GGUF files start with the four-byte ASCII magic "GGUF". A truncated or
    // corrupted download fails this check; delete so a retry redownloads cleanly.
    private func verifyModelIntegrity() throws {
        guard let path = AppController.shared.manager.llmModelPath(modelId: Self.modelId) else {
            throw LocalInstallerError.modelMissing
        }
        let url = URL(fileURLWithPath: path)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 4) ?? Data()
        let magic: [UInt8] = [0x47, 0x47, 0x55, 0x46]
        guard Array(header) == magic else {
            try? AppController.shared.manager.deleteLlm(modelId: Self.modelId)
            throw LocalInstallerError.corruptModel
        }
    }

    private func downloadModel() async throws {
        let modelId = Self.modelId
        let bridge = LlmProgressBridge { [weak self] info in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if info.totalBytes > 0 { self.modelTotal = info.totalBytes }
                self.modelDone = info.bytesDownloaded
                self.recompute()
            }
        }
        try await Task.detached(priority: .userInitiated) {
            try AppController.shared.manager.downloadLlm(modelId: modelId, callback: bridge)
        }.value
    }

    private func downloadBinary(asset: (url: URL, size: UInt64)) async throws {
        let dest = LlamaServerManager.shared.binaryPath()
        try await LlamaServerManager.shared.downloadBinary(
            to: dest,
            onBytesProgress: { [weak self] done, total in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.binaryDone = done
                    if total > 0 { self.binaryTotal = total }
                    self.recompute()
                }
            },
            knownAsset: asset
        )
    }

    private func recompute() {
        let total = modelTotal + binaryTotal
        let done = modelDone + binaryDone
        let frac = total > 0 ? min(1.0, Double(done) / Double(total)) : 0
        status = .downloading(fraction: frac, bytesDone: done, bytesTotal: total)
    }
}

enum LocalInstallerError: LocalizedError {
    case modelMissing
    case corruptModel

    var errorDescription: String? {
        switch self {
        case .modelMissing: return "Model file missing after download"
        case .corruptModel: return "Downloaded model is corrupt - please retry"
        }
    }
}
