import XCTest
@testable import WisprCore

private final class ProtocolStub: URLProtocol {
    static var received: URLRequest?
    static var body = #"{"choices":[{"message":{"content":"A polished sentence."}}]}"#
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.received = request
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class PolisherTests: XCTestCase {
    func testLocalModelReceivesTextAndReturnsEditedOutput() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ProtocolStub.self]
        ProtocolStub.body = #"{"choices":[{"message":{"content":"A polished sentence."}}]}"#
        let output = try await Polisher(session: URLSession(configuration: config)).polish(
            "a sentence", style: .professional,
            configuration: .init(endpoint: "http://localhost:11434/v1/chat/completions", model: "local-model"))
        XCTAssertEqual(output, "A polished sentence.")
        XCTAssertEqual(ProtocolStub.received?.httpMethod, "POST")
        XCTAssertNil(ProtocolStub.received?.value(forHTTPHeaderField: "Authorization"))
    }
    func testEmptyModelOutputCannotReplaceTranscript() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ProtocolStub.self]
        ProtocolStub.body = #"{"choices":[{"message":{"content":""}}]}"#
        do {
            _ = try await Polisher(session: URLSession(configuration: config)).polish("keep this", style: .natural,
                configuration: .init(endpoint: "http://localhost:11434/v1/chat/completions", model: "local"))
            XCTFail("Empty output must fail")
        } catch { XCTAssertTrue(error is PolishError) }
    }
}
