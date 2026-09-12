import SwiftUI
import UIKit

/// Lets a Console row be dragged out as a new window on iPad: the row vends
/// its Agent's user activity, and dropping it at the screen edge asks the
/// system for a window restored to that Agent. Off where multiple windows
/// are unsupported, so an iPhone row drags nowhere.
struct AgentWindowDrag: ViewModifier {
    let route: AgentRoute
    let title: String
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.onDrag {
                let provider = NSItemProvider()
                provider.registerObject(route.makeUserActivity(title: title), visibility: .all)
                return provider
            }
        } else {
            content
        }
    }
}
