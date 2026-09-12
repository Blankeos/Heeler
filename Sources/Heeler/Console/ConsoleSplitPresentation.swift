import SwiftUI

/// Layout policy uses the scene's available bounds, including iPad multitasking.
struct ConsoleSplitPresentation: Equatable {
    enum Style: Equatable {
        case automatic, balanced, prominentDetail
    }

    struct ColumnWidth: Equatable {
        let minimum: CGFloat
        let ideal: CGFloat
        let maximum: CGFloat?
    }

    let style: Style
    let defaultVisibility: NavigationSplitViewVisibility
    let sidebarWidth: ColumnWidth

    init(horizontalSizeClass: UserInterfaceSizeClass?, size: CGSize, hasSelection: Bool) {
        guard horizontalSizeClass == .regular else {
            style = .automatic
            defaultVisibility = .automatic
            sidebarWidth = ColumnWidth(minimum: 320, ideal: 380, maximum: nil)
            return
        }
        if size.width > size.height {
            style = .balanced
            defaultVisibility = .all
            sidebarWidth = ColumnWidth(minimum: 320, ideal: 380, maximum: 440)
        } else {
            style = .prominentDetail
            defaultVisibility = hasSelection ? .detailOnly : .all
            sidebarWidth = ColumnWidth(minimum: 320, ideal: 380, maximum: 400)
        }
    }
}

/// A default is applied once; rotation and selection never overwrite the user's toggle.
struct ConsoleSplitVisibilityState {
    private(set) var visibility: NavigationSplitViewVisibility = .automatic
    private(set) var isSeeded = false

    mutating func seed(from presentation: ConsoleSplitPresentation) {
        guard !isSeeded else { return }
        visibility = presentation.defaultVisibility
        isSeeded = true
    }

    mutating func setVisibility(_ visibility: NavigationSplitViewVisibility) {
        self.visibility = visibility
        isSeeded = true
    }
}

struct ConsoleNavigationSplitViewStyle: NavigationSplitViewStyle {
    let style: ConsoleSplitPresentation.Style

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        switch style {
        case .automatic:
            AutomaticNavigationSplitViewStyle().makeBody(configuration: configuration)
        case .balanced:
            BalancedNavigationSplitViewStyle().makeBody(configuration: configuration)
        case .prominentDetail:
            ProminentDetailNavigationSplitViewStyle().makeBody(configuration: configuration)
        }
    }
}
