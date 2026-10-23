import XCTest
@testable import WisprCore

final class TextFormatterTests: XCTestCase {
    let formatter = TextFormatter()

    func testRemovesOnlyUnambiguousFillersAndCleansSpacing() {
        XCTAssertEqual(formatter.format(" um, hello   there uh " ), "Hello there.")
        XCTAssertEqual(formatter.format("I like this idea"), "I like this idea.")
    }

    func testSpokenPunctuationAndParagraphs() {
        XCTAssertEqual(formatter.format("hello comma world new paragraph are you ready question mark"),
                       "Hello, world\n\nAre you ready?")
    }

    func testPreservesMeaningAndExistingPunctuation() {
        XCTAssertEqual(formatter.format("Don't change the API, version 2.4!"), "Don't change the API, version 2.4!")
        XCTAssertEqual(formatter.format("i think i can"), "I think I can.")
        XCTAssertEqual(formatter.format(""), "")
    }

    func testBulletsPreserveItemsAndDoNotSplitDecimalNumbers() {
        XCTAssertEqual(formatter.format("send version 2.4 new line review the API", style: .bullets),
                       "• Send version 2.4\n• Review the API")
    }

    func testNonEnglishDoesNotInterpretEnglishCommands() {
        XCTAssertEqual(formatter.format("new line", locale: "fr-FR"), "New line.")
    }

    func testUnknownLanguageDoesNotErasePortugueseArticles() {
        XCTAssertEqual(formatter.format("um carro", locale: "auto"), "Um carro.")
        XCTAssertEqual(formatter.format("um carro", locale: "pt"), "Um carro.")
        XCTAssertEqual(formatter.format("hello full stop are you ready question mark"), "Hello. Are you ready?")
    }

    func testEndpointRejectsInsecureRemoteAndEmbeddedCredentials() {
        XCTAssertNotNil(EndpointPolicy.validate("https://example.com/v1/chat/completions"))
        XCTAssertNotNil(EndpointPolicy.validate("http://localhost:1234/v1/chat/completions"))
        XCTAssertNotNil(EndpointPolicy.validate("http://127.0.0.1:1234/v1/chat/completions"))
        XCTAssertNil(EndpointPolicy.validate("http://example.com/v1/chat/completions"))
        XCTAssertNil(EndpointPolicy.validate("https://key:secret@example.com/path"))
        XCTAssertNil(EndpointPolicy.validate("file:///tmp/anything"))
        XCTAssertNil(EndpointPolicy.validate("https://example.com/path?api_key=secret"))
    }
}
