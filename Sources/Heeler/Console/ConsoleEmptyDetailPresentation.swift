import SwiftUI

struct ConsoleEmptyDetailPresentation: Equatable {
    enum Action: String, CaseIterable, Identifiable {
        case newAgent, hosts

        var id: Self { self }
        var title: String { self == .newAgent ? "New Agent" : "Hosts" }
        var systemImage: String { self == .newAgent ? "plus" : "server.rack" }
        var shortcutHint: String { self == .newAgent ? "⌘N" : "⌘⇧H" }
    }

    let title = "No Agent Selected"
    let systemImage = "rectangle.on.rectangle"
    let message: String
    let canStartAgent: Bool
    let actions = Action.allCases

    init(hasHosts: Bool) {
        canStartAgent = hasHosts
        message = hasHosts
            ? "Choose an Agent or start a new one to view its live terminal."
            : "Add a Host to start an Agent and view its live terminal."
    }

    func isEnabled(_ action: Action) -> Bool {
        action != .newAgent || canStartAgent
    }
}

struct ConsoleEmptyDetailView: View {
    let presentation: ConsoleEmptyDetailPresentation
    let perform: (ConsoleEmptyDetailPresentation.Action) -> Void

    var body: some View {
        ContentUnavailableView {
            Label(presentation.title, systemImage: presentation.systemImage)
        } description: {
            Text(presentation.message)
        } actions: {
            ForEach(presentation.actions) { action in
                Button {
                    perform(action)
                } label: {
                    HStack {
                        Label(action.title, systemImage: action.systemImage)
                        Text(action.shortcutHint)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!presentation.isEnabled(action))
                .hoverEffect(.highlight)
            }
        }
    }
}
