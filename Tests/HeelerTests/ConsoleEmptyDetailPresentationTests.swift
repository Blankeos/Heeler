import Testing

@testable import Heeler

@Suite("Console empty detail presentation")
struct ConsoleEmptyDetailPresentationTests {
    @Test func configuredConsoleOffersShowAgentsAndExistingActions() {
        let presentation = ConsoleEmptyDetailPresentation(hasHosts: true)
        #expect(presentation.title == "No Agent Selected")
        #expect(!presentation.message.isEmpty)
        #expect(!presentation.systemImage.isEmpty)
        #expect(presentation.actions == [.showAgents, .newAgent, .hosts])
        #expect(presentation.actions.map(\.title) == ["Show Agents", "New Agent", "Hosts"])
        #expect(presentation.actions.compactMap(\.shortcutHint) == ["⌘N", "⌘⇧H"])
        #expect(presentation.actions.allSatisfy { presentation.isEnabled($0) })
    }

    @Test func noHostsExplainsPrerequisiteAndKeepsHostsActionEnabled() {
        let presentation = ConsoleEmptyDetailPresentation(hasHosts: false)
        #expect(presentation.message == "Add a Host to start an Agent and view its live terminal.")
        #expect(presentation.actions == [.showAgents, .newAgent, .hosts])
        #expect(!presentation.isEnabled(.newAgent))
        #expect(presentation.isEnabled(.hosts))
        #expect(presentation.isEnabled(.showAgents))
    }
    @Test func visibleSidebarOmitsShowAgentsWithoutChangingOtherActions() {
        let presentation = ConsoleEmptyDetailPresentation(hasHosts: true, showsAgentsAction: false)
        #expect(presentation.actions == [.newAgent, .hosts])
    }

    @Test func showAgentsHasNoInventedKeyboardShortcut() {
        #expect(ConsoleEmptyDetailPresentation.Action.showAgents.title == "Show Agents")
        #expect(ConsoleEmptyDetailPresentation.Action.showAgents.systemImage == "sidebar.left")
        #expect(ConsoleEmptyDetailPresentation.Action.showAgents.shortcutHint == nil)
    }
}
