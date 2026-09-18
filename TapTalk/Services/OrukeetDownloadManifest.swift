import Foundation
import CryptoKit

struct OrukeetDownloadManifest: Decodable, Sendable {
    static let revision = "43142dd1897f9ddadcd70173fcb5ff45c08aa951"
    static let filename = "orukeet-r3-coreml-greedy.zip"
    static let expectedSHA256 = "beccdc6f18c4b10527a764f6e3ab12e3e11b969220c0cee175b3bb7eaa94290e"
    private static let maximumBytes = 64 * 1024

    struct Archive: Decodable, Sendable {
        let filename: String
        let bytes: Int64
        let sha256: String

        func matches(file: URL) throws -> Bool {
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard size.map(Int64.init) == bytes else { return false }
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            var hasher = SHA256()
            while true {
                try Task.checkCancellation()
                let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined() == sha256
        }
    }

    let repo_id: String
    let archives: [String: Archive]

    enum ManifestError: LocalizedError {
        case invalid
        var errorDescription: String? { "Orukeet download metadata is invalid - please retry" }
    }

    static func url(for filename: String) -> URL {
        guard let url = URL(string: "https://huggingface.co/oruk/orukeet/resolve/\(revision)/coreml/\(filename)") else {
            preconditionFailure("Orukeet download URL literal is malformed")
        }
        return url
    }

    static func load(session: URLSession = .shared) async throws -> Archive {
        let request = URLRequest(url: url(for: "manifest.json"), timeoutInterval: 30)
        let (stream, response) = try await session.bytes(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              response.expectedContentLength <= maximumBytes else { throw ManifestError.invalid }
        var data = Data()
        for try await byte in stream {
            guard data.count < maximumBytes else { throw ManifestError.invalid }
            data.append(byte)
        }
        try Task.checkCancellation()
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> Archive {
        guard data.count <= maximumBytes else { throw ManifestError.invalid }
        let manifest = try JSONDecoder().decode(Self.self, from: data)
        guard manifest.repo_id == "oruk/orukeet", let archive = manifest.archives["greedy"],
              archive.filename == filename, archive.bytes > 0,
              archive.sha256 == expectedSHA256 else { throw ManifestError.invalid }
        return archive
    }
}
