import XCTest
@testable import WisprCore

final class TextFormatterTests: XCTestCase {
    let formatter = TextFormatter()

    func testRemovesOnlyUnambiguousFillersAndCleansSpacing() {
        XCTAssertEqual(formatter.format(" um, hello   there uh "), "Hello there.")
        XCTAssertEqual(formatter.format("I like this idea"), "I like this idea.")
    }
    func testSpokenCommandsRequireExplicitOptIn() {
        XCTAssertEqual(formatter.format("I am researching colon cancer"), "I am researching colon cancer.")
        XCTAssertEqual(formatter.format("Use a comma in the new paragraph"), "Use a comma in the new paragraph.")
        XCTAssertEqual(formatter.format("hello comma world new paragraph are you ready question mark",
                                        interpretCommands: true), "Hello, world\n\nAre you ready?")
    }
    func testPreservesNamesAndExistingPunctuation() {
        XCTAssertEqual(formatter.format("iPhone battery is low"), "iPhone battery is low.")
        XCTAssertEqual(formatter.format("eBay order arrived"), "eBay order arrived.")
        XCTAssertEqual(formatter.format("Don't change the API, version 2.4!"), "Don't change the API, version 2.4!")
        XCTAssertEqual(formatter.format("i think i can"), "I think I can.")
        XCTAssertEqual(formatter.format(""), "")
    }
    func testPreservesStructuredSpans() {
        let cases = [
            "Use https://example.com?foo=bar",
            "Open example.com?foo=bar",
            "Send to first.last+tag@example.com",
            "Open ~/Desktop/my_report.txt",
            "Read src/audio_pipeline.py",
            "Run \u{0060}let i = 1;print(i)\u{0060}",
            "Keep \u{0060}\u{0060}\u{0060}let i = 1\nprint(i)\u{0060}\u{0060}\u{0060} unchanged."
        ]
        for text in cases { XCTAssertEqual(formatter.format(text), text, text) }
        XCTAssertEqual(formatter.format("https://example.com/colon?new=paragraph", interpretCommands: true),
                       "https://example.com/colon?new=paragraph")
    }
    func testBulletsPreserveItemsAndDoNotSplitDecimalNumbers() {
        XCTAssertEqual(formatter.format("send version 2.4 new line review the API", style: .bullets,
                                        interpretCommands: true), "• Send version 2.4\n• Review the API")
    }
    func testNonEnglishAndUnknownLanguageDoNotInterpretEnglishCommands() {
        XCTAssertEqual(formatter.format("new line", locale: "fr-FR", interpretCommands: true), "New line.")
        XCTAssertEqual(formatter.format("um carro", locale: "auto"), "Um carro.")
        XCTAssertEqual(formatter.format("um carro", locale: "pt"), "Um carro.")
        XCTAssertEqual(formatter.format("hello full stop are you ready question mark", interpretCommands: true),
                       "Hello. Are you ready?")
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
