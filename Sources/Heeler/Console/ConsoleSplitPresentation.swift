import SwiftUI

/// Layout policy uses scene bounds; the split style itself stays constant.
struct ConsoleSplitPresentation: Equatable {
    struct ColumnWidth: Equatable {
        let minimum: CGFloat
        let ideal: CGFloat
        let maximum: CGFloat?
    }

    let hasUsableSize: Bool
    let showsSidebarToggle: Bool
    let defaultVisibility: NavigationSplitViewVisibility
    let sidebarWidth: ColumnWidth

    init(
        horizontalSizeClass: UserInterfaceSizeClass?, size: CGSize,
        safeAreaInsets: EdgeInsets = EdgeInsets()
    ) {
        let width = size.width + safeAreaInsets.leading + safeAreaInsets.trailing
        let height = size.height + safeAreaInsets.top + safeAreaInsets.bottom
        // Insets must not turn an initial zero-sized layout pass into a valid seed.
        hasUsableSize = size.width > 0 && size.height > 0
            && width.isFinite && height.isFinite
        showsSidebarToggle = horizontalSizeClass == .regular
        guard hasUsableSize, horizontalSizeClass == .regular else {
            defaultVisibility = .automatic
            sidebarWidth = ColumnWidth(minimum: 320, ideal: 380, maximum: nil)
            return
        }
        if width > height {
            defaultVisibility = .all
            sidebarWidth = ColumnWidth(minimum: 320, ideal: 380, maximum: 440)
        } else {
            defaultVisibility = .detailOnly
            sidebarWidth = ColumnWidth(minimum: 320, ideal: 380, maximum: 400)
        }
    }
}

/// Layout defaults follow the scene until an explicit sidebar button press.
/// System binding write-backs report visibility without claiming user intent.
struct ConsoleSplitVisibilityState {
    private(set) var visibility: NavigationSplitViewVisibility = .automatic
    private(set) var userVisibility: NavigationSplitViewVisibility?

    var sidebarToggleTitle: String {
        visibility == .detailOnly ? "Show Sidebar" : "Hide Sidebar"
    }

    mutating func update(from presentation: ConsoleSplitPresentation) {
        guard presentation.hasUsableSize else { return }
        visibility = userVisibility ?? presentation.defaultVisibility
    }

    mutating func systemDidChangeVisibility(_ visibility: NavigationSplitViewVisibility) {
        self.visibility = visibility
    }

    mutating func toggleSidebar() {
        let next: NavigationSplitViewVisibility = visibility == .detailOnly ? .all : .detailOnly
        userVisibility = next
        visibility = next
    }
}
