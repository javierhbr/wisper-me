import XCTest
@testable import WisprCore

final class HTTPPolicyTests: XCTestCase {
    func testCredentialOriginNormalizesEffectivePortsAndSeparatesDestinations() {
        XCTAssertEqual(EndpointOrigin.key(for: "https://EXAMPLE.com/v1/chat/completions"), "https://example.com:443")
        XCTAssertEqual(EndpointOrigin.key(for: "https://example.com:443/other"), "https://example.com:443")
        XCTAssertEqual(EndpointOrigin.key(for: "http://localhost:11434/v1/chat/completions"), "http://localhost:11434")
        XCTAssertEqual(EndpointOrigin.key(for: "http://[::1]:11434/path"), "http://[::1]:11434")
        XCTAssertNotEqual(EndpointOrigin.key(for: "https://example.com"), EndpointOrigin.key(for: "https://other.example"))
        XCTAssertNotEqual(EndpointOrigin.key(for: "http://localhost:11434"), EndpointOrigin.key(for: "http://localhost:1234"))
        XCTAssertNil(EndpointOrigin.key(for: "http://remote.example/api"))
        XCTAssertNil(EndpointOrigin.key(for: "https://secret:token@example.com/api"))
        XCTAssertNil(EndpointOrigin.key(for: "https://example.com/api?key=secret"))
        XCTAssertNil(EndpointOrigin.key(for: "https://example.com:0/api"))
    }

    func testOwnedTransportUsesBoundedEphemeralConfiguration() {
        let config = HTTPClient.configuration(protocolClasses: nil)
        XCTAssertNil(config.httpCookieStorage)
        XCTAssertNil(config.urlCache)
        XCTAssertNil(config.urlCredentialStorage)
        XCTAssertFalse(config.httpShouldSetCookies)
        XCTAssertEqual(config.timeoutIntervalForRequest, 45)
        XCTAssertEqual(config.timeoutIntervalForResource, 60)
    }
}
