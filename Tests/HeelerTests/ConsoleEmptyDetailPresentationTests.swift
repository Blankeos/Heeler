import Testing

@testable import Heeler

@Suite("Console empty detail presentation")
struct ConsoleEmptyDetailPresentationTests {
    @Test func configuredConsoleOffersNewAgentAndHostsWithShortcutHints() {
        let presentation = ConsoleEmptyDetailPresentation(hasHosts: true)
        #expect(presentation.title == "No Agent Selected")
        #expect(!presentation.message.isEmpty)
        #expect(!presentation.systemImage.isEmpty)
        #expect(presentation.actions == [.newAgent, .hosts])
        #expect(presentation.actions.map(\.title) == ["New Agent", "Hosts"])
        #expect(presentation.actions.map(\.shortcutHint) == ["⌘N", "⌘⇧H"])
        #expect(presentation.actions.allSatisfy { presentation.isEnabled($0) })
    }

    @Test func noHostsExplainsPrerequisiteAndKeepsHostsActionEnabled() {
        let presentation = ConsoleEmptyDetailPresentation(hasHosts: false)
        #expect(presentation.message == "Add a Host to start an Agent and view its live terminal.")
        #expect(presentation.actions == [.newAgent, .hosts])
        #expect(!presentation.isEnabled(.newAgent))
        #expect(presentation.isEnabled(.hosts))
    }
}
