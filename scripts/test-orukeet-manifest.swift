import Foundation

private enum TestFailure: Error { case assertion(String) }

private func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
    guard value() else { throw TestFailure.assertion(message) }
}

private final class ManifestProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responseCode = 200
    nonisolated(unsafe) private static var responseBody = Data()
    nonisolated(unsafe) private static var holdResponse = false
    nonisolated(unsafe) private static var requests = [URLRequest]()

    static func configure(code: Int = 200, body: Data, hold: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        responseCode = code
        responseBody = body
        holdResponse = hold
        requests = []
    }

    static func recordedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let code = Self.responseCode
        let data = Self.responseBody
        let hold = Self.holdResponse
        Self.lock.unlock()
        guard !hold else { return }
        guard let url = request.url, let response = HTTPURLResponse(
            url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: nil
        ) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
private enum ManifestTests {
    static func main() async throws {
        let valid = Data("""
        {"repo_id":"oruk/orukeet","archives":{"greedy":{
          "filename":"orukeet-r3-coreml-greedy.zip","bytes":466579943,
          "sha256":"beccdc6f18c4b10527a764f6e3ab12e3e11b969220c0cee175b3bb7eaa94290e"
        }}}
        """.utf8)
        let archive = try OrukeetDownloadManifest.decode(valid)
        try check(archive.bytes == 466579943, "Manifest byte count must be consumed")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("abc".utf8).write(to: file)
        let smallArchive = OrukeetDownloadManifest.Archive(
            filename: "fixture.zip", bytes: 3,
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let match = try smallArchive.matches(file: file)
        try check(match, "Valid size and SHA-256 must pass")
        try Data("abd".utf8).write(to: file)
        let corrupt = try smallArchive.matches(file: file)
        try check(!corrupt, "Equal-size corruption must fail SHA-256")
        try Data("abcd".utf8).write(to: file)
        let oversized = try smallArchive.matches(file: file)
        try check(!oversized, "Wrong byte count must fail")
        let text = String(decoding: valid, as: UTF8.self)
        let invalid = [
            Data("not JSON".utf8),
            Data(text.replacingOccurrences(of: "oruk/orukeet", with: "other/model").utf8),
            Data(text.replacingOccurrences(of: "\"greedy\"", with: "\"baseline\"").utf8),
            Data(text.replacingOccurrences(of: "orukeet-r3-coreml-greedy.zip", with: "../other.zip").utf8),
            Data(text.replacingOccurrences(of: "466579943", with: "0").utf8),
            Data(text.replacingOccurrences(of: "466579943", with: "-1").utf8),
            Data(text.replacingOccurrences(of: "beccdc6f", with: "00000000").utf8),
            Data(repeating: 32, count: 65537)
        ]
        for (index, data) in invalid.enumerated() {
            do {
                _ = try OrukeetDownloadManifest.decode(data)
                throw TestFailure.assertion("Invalid manifest \(index) accepted")
            } catch is TestFailure { throw TestFailure.assertion("Invalid manifest \(index) accepted") }
            catch {}
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ManifestProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        ManifestProtocol.configure(body: valid)
        let loaded = try await OrukeetDownloadManifest.load(session: session)
        try check(loaded.sha256 == archive.sha256, "Downloaded manifest changed hash")
        let request = ManifestProtocol.recordedRequests()
        try check(request.count == 1, "Must request exactly one required manifest")
        try check(request.first?.url?.absoluteString ==
            "https://huggingface.co/oruk/orukeet/resolve/43142dd1897f9ddadcd70173fcb5ff45c08aa951/coreml/manifest.json",
            "Manifest URL must be immutable and canonical")
        try check(request.first?.timeoutInterval == 30, "Manifest request needs a timeout")
        ManifestProtocol.configure(code: 404, body: valid)
        do {
            _ = try await OrukeetDownloadManifest.load(session: session)
            throw TestFailure.assertion("HTTP failure accepted")
        } catch is TestFailure { throw TestFailure.assertion("HTTP failure accepted") }
        catch {}
        ManifestProtocol.configure(body: Data(repeating: 32, count: 65537))
        do {
            _ = try await OrukeetDownloadManifest.load(session: session)
            throw TestFailure.assertion("Oversized streamed body accepted")
        } catch is TestFailure { throw TestFailure.assertion("Oversized streamed body accepted") }
        catch {}
        ManifestProtocol.configure(body: valid, hold: true)
        let cancelled = Task { try await OrukeetDownloadManifest.load(session: session) }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            throw TestFailure.assertion("Cancelled request accepted")
        } catch is TestFailure { throw TestFailure.assertion("Cancelled request accepted") }
        catch is CancellationError {}
        catch let error as URLError where error.code == .cancelled {}
        if let path = ProcessInfo.processInfo.environment["ORUKEET_TEST_ARCHIVE"] {
            let cachedMatch = try archive.matches(file: URL(fileURLWithPath: path))
            try check(cachedMatch, "Published cached model archive must match")
            print("PASS: published model archive SHA-256 and byte count")
        }
        print("PASS: valid metadata, 8 invalid variants, 3 integrity checks, pinned request, HTTP failure, stream cap, cancellation")
    }
}
