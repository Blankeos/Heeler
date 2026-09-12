import SwiftUI

struct ConsoleEmptyDetailPresentation: Equatable {
    enum Action: String, CaseIterable, Identifiable {
        case showAgents, newAgent, hosts

        var id: Self { self }
        var title: String {
            switch self {
            case .showAgents: "Show Agents"
            case .newAgent: "New Agent"
            case .hosts: "Hosts"
            }
        }
        var systemImage: String {
            switch self {
            case .showAgents: "sidebar.left"
            case .newAgent: "plus"
            case .hosts: "server.rack"
            }
        }
        var shortcutHint: String? {
            switch self {
            case .showAgents: nil
            case .newAgent: "⌘N"
            case .hosts: "⌘⇧H"
            }
        }
    }

    let title = "No Agent Selected"
    let systemImage = "rectangle.on.rectangle"
    let message: String
    let canStartAgent: Bool
    let actions: [Action]

    init(hasHosts: Bool, showsAgentsAction: Bool = true) {
        actions = showsAgentsAction ? Action.allCases : [.newAgent, .hosts]
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
                        if let hint = action.shortcutHint {
                            Text(hint)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!presentation.isEnabled(action))
                .hoverEffect(.highlight)
            }
        }
    }
}
