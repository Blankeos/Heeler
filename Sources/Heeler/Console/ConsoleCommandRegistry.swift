import Observation
import SwiftUI

/// Created by each Console, never shared between windows. Tokens prevent outgoing
/// views from removing the replacement view's registration during navigation.
@MainActor
@Observable
final class ConsoleCommandRegistry {
    struct Terminal {
        let token: UUID
        let agentID: ConsoleAgent.ID
        let isFocused: Bool
        let isAvailable: @MainActor () -> Bool
        let toggleInputMode: @MainActor () -> Void
    }

    struct Composer {
        let token: UUID
        let terminalToken: UUID
        let agentID: ConsoleAgent.ID
        let isFocused: Bool
        let hasDraft: @MainActor () -> Bool
        let send: @MainActor () async -> Void
    }

    private(set) var terminal: Terminal?
    private(set) var composer: Composer?

    func register(_ terminal: Terminal) { self.terminal = terminal }
    func register(_ composer: Composer) { self.composer = composer }

    func removeTerminal(_ token: UUID) {
        guard terminal?.token == token else { return }
        terminal = nil
    }

    func removeComposer(_ token: UUID) {
        guard composer?.token == token else { return }
        composer = nil
    }
}

private struct ConsoleCommandRegistryKey: EnvironmentKey {
    static let defaultValue: ConsoleCommandRegistry? = nil
}

private struct ConsoleCommandTerminalTokenKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    var consoleCommandRegistry: ConsoleCommandRegistry? {
        get { self[ConsoleCommandRegistryKey.self] }
        set { self[ConsoleCommandRegistryKey.self] = newValue }
    }

    var consoleCommandTerminalToken: UUID? {
        get { self[ConsoleCommandTerminalTokenKey.self] }
        set { self[ConsoleCommandTerminalTokenKey.self] = newValue }
    }
}

/// Live reads recheck selection, draft and registrations when an action fires,
/// including after the menu was opened or an asynchronous Send was scheduled.
@MainActor
struct ConsoleCommandTarget {
    struct Context {
        let selection: ConsoleAgent.ID?
        let agents: [ConsoleAgent.ID]
        let isSearchFocused: Bool
        let isCovered: Bool
        let inputMode: AgentInputMode
    }

    let registry: ConsoleCommandRegistry
    let context: @MainActor () -> Context
    let navigate: @MainActor (ConsoleAgent.ID) -> Void
    let focusSearch: @MainActor () -> Void
    let newAgent: @MainActor () -> Void
    let settings: @MainActor () -> Void
    let hosts: @MainActor () -> Void
    let closeAgent: @MainActor () -> Void

    private var activeTerminal: ConsoleCommandRegistry.Terminal? {
        guard let terminal = registry.terminal,
            terminal.agentID == context().selection, terminal.isAvailable()
        else { return nil }
        return terminal
    }

    private var activeComposer: ConsoleCommandRegistry.Composer? {
        guard let terminal = activeTerminal, let composer = registry.composer,
            composer.agentID == terminal.agentID, composer.terminalToken == terminal.token
        else { return nil }
        return composer
    }

    func allows(_ action: ConsoleCommandAction) -> Bool {
        let context = context()
        guard !context.isCovered else { return false }
        let terminal = activeTerminal
        let composer = activeComposer
        // During a responder handoff, a pending Composer blur must not let
        // Send win over an already-focused search field or terminal.
        let focus: ConsoleCommandFocus
        if context.isSearchFocused {
            focus = .sidebar
        } else if terminal?.isFocused == true {
            focus = .terminal
        } else if composer?.isFocused == true {
            focus = .composer
        } else {
            focus = .none
        }
        let availability = ConsoleCommandAvailability(
            focus: focus, hasSelection: context.selection != nil,
            agentCount: context.agents.count,
            inputMode: context.inputMode,
            hasDraft: composer?.hasDraft() ?? false)
        guard availability.allows(action) else { return false }
        switch action {
        case .toggleInputMode: return terminal != nil
        case .sendDraft: return composer != nil
        default: return true
        }
    }

    func perform(_ action: ConsoleCommandAction) {
        guard allows(action) else { return }
        switch action {
        case .selectAgent, .previousAgent, .nextAgent:
            let context = context()
            if let id = ConsoleCommandNavigation.destination(
                for: action, in: context.agents, selection: context.selection)
            {
                navigate(id)
            }
        case .focusSearch: focusSearch()
        case .newAgent: newAgent()
        case .settings: settings()
        case .hosts: hosts()
        case .toggleInputMode: activeTerminal?.toggleInputMode()
        case .closeAgent: closeAgent()
        case .sendDraft:
            guard let composer = activeComposer else { return }
            Task { await sendDraft(for: composer.token) }
        }
    }

    func sendDraft(for token: UUID) async {
        guard allows(.sendDraft), let composer = activeComposer, composer.token == token else {
            return
        }
        await composer.send()
    }
}

/// These hooks observe existing focus signals; they never participate in key dispatch.
struct ConsoleTerminalCommandRegistration: ViewModifier {
    let agentID: ConsoleAgent.ID
    let isFocused: Bool
    let isAvailable: Bool
    let isOnStage: @MainActor () -> Bool
    let toggleInputMode: @MainActor () -> Void
    @Environment(\.consoleCommandRegistry) private var registry
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .environment(\.consoleCommandTerminalToken, token)
            .onAppear { register() }
            .onChange(of: isFocused) { _, _ in update() }
            .onChange(of: isAvailable) { _, _ in update() }
            .onDisappear { registry?.removeTerminal(token) }
    }

    private func update() {
        guard registry?.terminal?.token == token else { return }
        register()
    }

    private func register() {
        registry?.register(
            ConsoleCommandRegistry.Terminal(
                token: token, agentID: agentID, isFocused: isFocused,
                isAvailable: { isAvailable && isOnStage() },
                toggleInputMode: toggleInputMode))
    }
}

struct ConsoleComposerCommandRegistration: ViewModifier {
    let agentID: ConsoleAgent.ID?
    let isFocused: Bool
    let hasDraft: @MainActor () -> Bool
    let send: @MainActor () async -> Void
    @Environment(\.consoleCommandRegistry) private var registry
    @Environment(\.consoleCommandTerminalToken) private var terminalToken
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { register() }
            .onChange(of: isFocused) { _, _ in
                guard registry?.composer?.token == token else { return }
                register()
            }
            .onDisappear { registry?.removeComposer(token) }
    }

    private func register() {
        guard let agentID, let terminalToken else { return }
        registry?.register(
            ConsoleCommandRegistry.Composer(
                token: token, terminalToken: terminalToken, agentID: agentID, isFocused: isFocused,
                hasDraft: hasDraft, send: send))
    }
}
