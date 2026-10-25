import XCTest
@testable import WisprMobileCore

final class RewriteGoalTests: XCTestCase {
    func testFiveGoalsIncludeTheRequestedStoryAndProfessionalChoices() {
        XCTAssertEqual(RewriteGoal.allCases, [.defaultClarity, .mainPointFirst, .clearStory, .professional, .custom])
        XCTAssertEqual(RewriteGoal.clearStory.rawValue, "Tell a clear story")
        XCTAssertEqual(RewriteGoal.professional.rawValue, "Professional message")
        XCTAssertEqual(RewriteGoal.allCases.map(\.id), RewriteGoal.allCases.map(\.rawValue))
        XCTAssertEqual(RewriteGoal.defaultClarity.rawValue, "Default")
        XCTAssertEqual(RewriteGoal.custom.rawValue, "Custom")
        XCTAssertTrue(RewriteGoal.allCases.allSatisfy { !$0.explanation.isEmpty })
    }

    func testDefaultRecomposesTheIdeaAndPreservesDetails() {
        let instructions = RewriteGoal.defaultClarity.directions(custom: "Ignored custom content")
        XCTAssertTrue(instructions.contains("Reorder ideas"))
        XCTAssertTrue(instructions.contains("improve transitions"))
        XCTAssertTrue(instructions.contains("remove genuine repetition"))
        XCTAssertTrue(instructions.contains("beyond grammar"))
        XCTAssertFalse(instructions.contains("Ignored custom content"))
        assertPreservation(instructions)
    }

    func testMainPointFirstHasDistinctOrganizationGoal() {
        let instructions = RewriteGoal.mainPointFirst.directions(custom: "")
        XCTAssertTrue(instructions.contains("main point first"))
        XCTAssertTrue(instructions.contains("supporting details"))
        XCTAssertNotEqual(instructions, RewriteGoal.defaultClarity.directions(custom: ""))
        assertPreservation(instructions)
    }

    func testCustomDirectionsKeepTheFullInputBudgetWithoutPresetFraming() {
        XCTAssertEqual(RewriteGoal.custom.directions(custom: "  Explain the timeline clearly.  "),
            "Explain the timeline clearly.")
        let custom = String(repeating: "x", count: 2_000)
        XCTAssertEqual(RewriteGoal.custom.directions(custom: custom), custom)
        XCTAssertEqual(RewriteGoal.custom.directions(custom: custom).utf8.count, 2_000)
        XCTAssertTrue(RewriteGoal.custom.explanation.contains("preservation rules"))
    }

    func testClearStoryDoesNotInventChronologyOrCausality() {
        let instructions = RewriteGoal.clearStory.directions(custom: "Ignored custom content")
        XCTAssertTrue(instructions.contains("coherent narrative"))
        XCTAssertTrue(instructions.contains("stated events"))
        XCTAssertTrue(instructions.contains("Do not invent chronology, causality, or dialogue"))
        XCTAssertFalse(instructions.contains("Ignored custom content"))
        assertPreservation(instructions)
    }

    func testProfessionalMessagePreservesUncertaintyAndDoesNotCreateCommitments() {
        let instructions = RewriteGoal.professional.directions(custom: "")
        XCTAssertTrue(instructions.contains("professional message"))
        XCTAssertTrue(instructions.contains("work"))
        XCTAssertTrue(instructions.contains("recipient"))
        XCTAssertTrue(instructions.contains("agreement"))
        XCTAssertTrue(instructions.contains("promises"))
        XCTAssertTrue(instructions.contains("commitments"))
        XCTAssertTrue(instructions.contains("remove repetition, not facts"))
        assertPreservation(instructions)
    }

    private func assertPreservation(_ instructions: String, file: StaticString = #filePath, line: UInt = #line) {
        for requirement in ["facts", "names", "numbers", "uncertainty", "intention",
                            "invent", "summariz", "original", "clipboard"] {
            XCTAssertTrue(instructions.contains(requirement), requirement, file: file, line: line)
        }
    }
}
