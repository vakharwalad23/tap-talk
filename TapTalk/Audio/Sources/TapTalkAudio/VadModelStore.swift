import CryptoKit
import Foundation

/// Why the Silero model could not be installed.
public enum VadModelError: LocalizedError, Equatable {
    case badURL(String)
    case download(String, Int)
    case checksum(String)

    public var errorDescription: String? {
        switch self {
        case .badURL(let url): return "Invalid model URL: \(url)"
        case .download(let file, let status): return "Model download failed for \(file) (HTTP \(status))"
        case .checksum(let file): return "Model file \(file) failed verification"
        }
    }
}

/// Installs the pinned Silero Core ML bundle into the app's models directory.
public struct VadModelStore: Sendable {
    /// One file of the compiled bundle with its verified size and SHA-256.
    public struct File: Sendable {
        public let path: String
        public let sha256: String
        public let size: Int

        public init(path: String, sha256: String, size: Int) {
            self.path = path
            self.sha256 = sha256
            self.size = size
        }
    }

    /// Immutable revision of FluidInference/silero-vad-coreml the hashes below were taken from.
    public static let pinnedBaseURL =
        "https://huggingface.co/FluidInference/silero-vad-coreml/resolve/b419383c55c110e2c9271fa6ee0ea83d03c70d96/silero-vad-unified-v6.0.0.mlmodelc/"

    /// Every file of the bundle at that revision.
    public static let pinnedFiles: [File] = [
        File(path: "analytics/coremldata.bin", sha256: "2141be60ea0adf7acb1232fbcfaffb2be308ae02e6672d3762aedf36611ea9fd", size: 243),
        File(path: "coremldata.bin", sha256: "f460dcdf796b19c04bc38ab6e69601831f634e5e74d499487f0c8fe17ca12f0f", size: 593),
        File(path: "metadata.json", sha256: "282b1b788b5d4d66d6a70d468464a7ada71d2469a8705526b741fd9ab841295a", size: 3_232),
        File(path: "model.mil", sha256: "79eea23c368f3e7edf85af798a953f5b0910e4b08ff48e55fff8545dd05fd047", size: 25_126),
        File(path: "weights/weight.bin", sha256: "853cf34740d3f5061f977ebe2976f7c921b064261c9c4753b3a1196f2dba42b4", size: 882_304),
    ]

    private let directory: URL
    private let files: [File]
    private let baseURL: String

    /// Store rooted at `<modelsDirectory>/silero-vad`.
    public init(modelsDirectory: URL, files: [File] = Self.pinnedFiles, baseURL: String = Self.pinnedBaseURL) {
        directory = modelsDirectory.appendingPathComponent("silero-vad", isDirectory: true)
        self.files = files
        self.baseURL = baseURL
    }

    /// Where the compiled bundle lives once installed.
    public var modelURL: URL { directory.appendingPathComponent(SileroVoiceActivity.bundleName, isDirectory: true) }

    private var partialURL: URL {
        directory.appendingPathComponent(SileroVoiceActivity.bundleName + ".partial", isDirectory: true)
    }

    /// Every pinned file present at its expected size; hashes are checked once, at install.
    public func isInstalled() -> Bool {
        files.allSatisfy { file in
            let path = modelURL.appendingPathComponent(file.path).path
            let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber
            return size?.intValue == file.size
        }
    }

    /// Removes a download that a previous run left unfinished.
    public func sweepResidue() {
        try? FileManager.default.removeItem(at: partialURL)
    }

    /// Downloads and verifies every file into a partial folder, then renames it into place.
    public func install(session: URLSession = .shared) async throws {
        let manager = FileManager.default
        sweepResidue()
        try manager.createDirectory(at: partialURL, withIntermediateDirectories: true)
        do {
            for file in files {
                guard let url = URL(string: baseURL + file.path) else { throw VadModelError.badURL(baseURL + file.path) }
                let (data, response) = try await session.data(from: url)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200 else { throw VadModelError.download(file.path, status) }
                guard data.count == file.size, Self.sha256(of: data) == file.sha256 else {
                    throw VadModelError.checksum(file.path)
                }
                let destination = partialURL.appendingPathComponent(file.path)
                try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: destination)
            }
            if manager.fileExists(atPath: modelURL.path) { try manager.removeItem(at: modelURL) }
            try manager.moveItem(at: partialURL, to: modelURL)
        } catch {
            sweepResidue()
            throw error
        }
    }

    private static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
