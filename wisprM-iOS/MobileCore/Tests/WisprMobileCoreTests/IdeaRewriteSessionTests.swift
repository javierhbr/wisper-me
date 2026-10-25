import XCTest
@testable import WisprMobileCore

final class IdeaRewriteSessionTests: XCTestCase {
    func testProviderSelectionIsIndependentOfAutomaticPolishing() {
        XCTAssertEqual(RewriteProvider.allCases.map(\.polishMode), [.appleIntelligence, .local, .server])
        XCTAssertEqual(RewriteProvider.allCases.map(\.id), RewriteProvider.allCases.map(\.rawValue))
        XCTAssertTrue(RewriteProvider.appleIntelligence.requiresForeground)
        XCTAssertTrue(RewriteProvider.local.requiresForeground)
        XCTAssertFalse(RewriteProvider.server.requiresForeground)
        XCTAssertFalse(RewriteProvider.allCases.contains { $0.polishMode == .off })
    }

    func testGeneratedProposalRemainsSeparateUntilAccepted() {
        var session = IdeaRewriteSession()
        let source = "First the details. The main point comes later."
        let attempt = session.begin(source: source)
        XCTAssertTrue(session.isGenerating)
        XCTAssertEqual(session.original, source)
        XCTAssertNil(session.proposal)
        XCTAssertFalse(session.canUndo(currentText: source))
        XCTAssertTrue(session.finish("The main point comes first, followed by the details.", attempt: attempt, currentText: source))
        XCTAssertFalse(session.isGenerating)
        XCTAssertEqual(session.original, source)
        XCTAssertEqual(session.proposal, "The main point comes first, followed by the details.")
        XCTAssertFalse(session.canUndo(currentText: source))
    }

    func testAcceptAndUndoRestoreExactOriginalOnce() {
        var session = IdeaRewriteSession()
        let source = "  Names and dates: Ana, May 3.\nI might attend.  "
        let result = "I might attend. Names and dates: Ana, May 3."
        let attempt = session.begin(source: source)
        XCTAssertTrue(session.finish(result, attempt: attempt, currentText: source))
        XCTAssertEqual(session.accept(currentText: source), result)
        XCTAssertNil(session.proposal)
        XCTAssertNil(session.original)
        XCTAssertTrue(session.canUndo(currentText: result))
        XCTAssertEqual(session.undo(currentText: result), source)
        XCTAssertFalse(session.canUndo(currentText: source))
        XCTAssertNil(session.undo(currentText: source))
    }

    func testCancellationRejectsLateCompletion() {
        var session = IdeaRewriteSession()
        let attempt = session.begin(source: "Original")
        session.cancel()
        XCTAssertFalse(session.isGenerating)
        XCTAssertNil(session.original)
        XCTAssertNil(session.proposal)
        XCTAssertFalse(session.finish("Late response", attempt: attempt, currentText: "Original"))
        XCTAssertNil(session.accept(currentText: "Original"))
    }

    func testRetryRejectsOlderResponseWithoutCancellingCurrentAttempt() {
        var session = IdeaRewriteSession()
        let first = session.begin(source: "Original")
        let second = session.begin(source: "Original")
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(session.finish("Old response", attempt: first, currentText: "Original"))
        XCTAssertTrue(session.isGenerating)
        XCTAssertTrue(session.finish("New response", attempt: second, currentText: "Original"))
        XCTAssertEqual(session.proposal, "New response")
        XCTAssertFalse(session.finish("Duplicate response", attempt: second, currentText: "Original"))
        XCTAssertEqual(session.proposal, "New response")
    }

    func testChangedTextRejectsCompletionAndAcceptance() {
        var session = IdeaRewriteSession()
        let attempt = session.begin(source: "Original")
        XCTAssertFalse(session.finish("A rewrite", attempt: attempt, currentText: "Edited manually"))
        XCTAssertFalse(session.isGenerating)
        XCTAssertNil(session.proposal)
        let next = session.begin(source: "Original")
        XCTAssertTrue(session.finish("A rewrite", attempt: next, currentText: "Original"))
        XCTAssertNil(session.accept(currentText: "Edited manually"))
        XCTAssertNil(session.proposal)
    }

    func testTextChangeInvalidatesAttemptEvenIfTextReturnsToOriginal() {
        var session = IdeaRewriteSession()
        let attempt = session.begin(source: "A")
        session.textChanged() // A -> B -> A must still invalidate the in-flight response.
        XCTAssertFalse(session.finish("Rewrite of A", attempt: attempt, currentText: "A"))
        XCTAssertNil(session.proposal)
    }

    func testManualEditInvalidatesUndo() {
        var session = acceptedSession()
        XCTAssertFalse(session.canUndo(currentText: "Manually edited rewrite"))
        XCTAssertNil(session.undo(currentText: "Manually edited rewrite"))
        session.textChanged()
        XCTAssertFalse(session.canUndo(currentText: "Rewritten"))
    }

    func testCancelledSecondRewritePreservesValidUndo() {
        var session = acceptedSession()
        let second = session.begin(source: "Rewritten")
        session.cancel()
        XCTAssertFalse(session.finish("Late second rewrite", attempt: second, currentText: "Rewritten"))
        XCTAssertTrue(session.canUndo(currentText: "Rewritten"))
        XCTAssertEqual(session.undo(currentText: "Rewritten"), "Original")
    }

    func testStartingFromUnrelatedTextDoesNotPreserveOldUndo() {
        var session = acceptedSession()
        _ = session.begin(source: "Another dictation")
        session.cancel()
        XCTAssertFalse(session.canUndo(currentText: "Rewritten"))
    }

    func testEmptyMalformedAndOversizedResponsesDoNotBecomeProposals() {
        for response in [" \n\t", "<think>unfinished", String(repeating: "x", count: 16_001)] {
            var session = IdeaRewriteSession()
            let attempt = session.begin(source: "Original")
            XCTAssertFalse(session.finish(response, attempt: attempt, currentText: "Original"))
            XCTAssertFalse(session.isGenerating)
            XCTAssertNil(session.proposal)
            XCTAssertNil(session.accept(currentText: "Original"))
        }
    }

    private func acceptedSession() -> IdeaRewriteSession {
        var session = IdeaRewriteSession()
        let attempt = session.begin(source: "Original")
        XCTAssertTrue(session.finish("Rewritten", attempt: attempt, currentText: "Original"))
        XCTAssertEqual(session.accept(currentText: "Original"), "Rewritten")
        return session
    }
}
