import CryptoKit
import XCTest
@testable import TapTalkAudio

final class VadModelStoreTests: XCTestCase {
    private var root = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        StubURLProtocol.responses = [:]
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testInstallVerifiesAndMovesEveryFileIntoPlace() async throws {
        let store = makeStore(serving: ["coremldata.bin": "abc", "weights/weight.bin": "weights"])
        try await store.install(session: session())
        XCTAssertTrue(store.isInstalled())
        XCTAssertEqual(try String(contentsOf: store.modelURL.appendingPathComponent("weights/weight.bin"), encoding: .utf8), "weights")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.modelURL.path + ".partial"))
    }

    func testChecksumMismatchLeavesNothingBehind() async throws {
        let store = makeStore(serving: ["coremldata.bin": "abc", "weights/weight.bin": "weights"],
                              override: ["weights/weight.bin": "tampered"])
        do {
            try await store.install(session: session())
            XCTFail("expected a checksum error")
        } catch {
            XCTAssertEqual(error as? VadModelError, .checksum("weights/weight.bin"))
        }
        XCTAssertFalse(store.isInstalled())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.modelURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.modelURL.path + ".partial"))
    }

    func testHTTPErrorIsReported() async throws {
        let store = makeStore(serving: ["coremldata.bin": "abc"], status: 404)
        do {
            try await store.install(session: session())
            XCTFail("expected a download error")
        } catch {
            XCTAssertEqual(error as? VadModelError, .download("coremldata.bin", 404))
        }
    }

    func testWrongSizedFileIsNotInstalled() async throws {
        let store = makeStore(serving: ["coremldata.bin": "abc"])
        try await store.install(session: session())
        try "abcd".write(to: store.modelURL.appendingPathComponent("coremldata.bin"), atomically: true, encoding: .utf8)
        XCTAssertFalse(store.isInstalled())
    }

    func testSweepRemovesAnInterruptedDownload() throws {
        let store = makeStore(serving: ["coremldata.bin": "abc"])
        let partial = URL(fileURLWithPath: store.modelURL.path + ".partial")
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
        store.sweepResidue()
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
    }

    func testPinnedTableMatchesTheVerifiedRevision() {
        XCTAssertEqual(VadModelStore.pinnedFiles.count, 5)
        XCTAssertEqual(VadModelStore.pinnedFiles.reduce(0) { $0 + $1.size }, 911_498)
        XCTAssertTrue(VadModelStore.pinnedBaseURL.contains("b419383c55c110e2c9271fa6ee0ea83d03c70d96"))
    }

    private func makeStore(serving files: [String: String], override: [String: String] = [:], status: Int = 200) -> VadModelStore {
        let table = files.keys.sorted().map { path -> VadModelStore.File in
            let data = Data((files[path] ?? "").utf8)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            StubURLProtocol.responses["https://stub.local/\(path)"] = (status, Data((override[path] ?? files[path] ?? "").utf8))
            return VadModelStore.File(path: path, sha256: digest, size: data.count)
        }
        return VadModelStore(modelsDirectory: root, files: table, baseURL: "https://stub.local/")
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [String: (Int, Data)] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let (status, data) = Self.responses[url.absoluteString],
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
