import SwiftUI

/// Layout policy uses scene bounds; the split style itself stays constant.
struct ConsoleSplitPresentation: Equatable {
    struct ColumnWidth: Equatable {
        let minimum: CGFloat
        let ideal: CGFloat
        let maximum: CGFloat?
    }

    let hasUsableSize: Bool
    let usesRegularColumns: Bool
    let layoutSize: CGSize
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
        usesRegularColumns = horizontalSizeClass == .regular
        layoutSize = CGSize(width: width, height: height)
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

/// Layout defaults follow the scene until a visibility change in a stable layout.
struct ConsoleSplitVisibilityState {
    private(set) var visibility: NavigationSplitViewVisibility = .automatic
    private(set) var userVisibility: NavigationSplitViewVisibility?
    private(set) var reportedSidebarVisibility: Bool?
    private var appliedPresentation: ConsoleSplitPresentation?

    var sidebarToggleTitle: String {
        switch reportedSidebarVisibility {
        case .some(true): "Hide Sidebar"
        case .some(false): "Show Sidebar"
        case nil: "Toggle Sidebar"
        }
    }

    mutating func update(from presentation: ConsoleSplitPresentation) {
        guard presentation.hasUsableSize else { return }
        if appliedPresentation != presentation {
            reportedSidebarVisibility = nil
        }
        appliedPresentation = presentation
        visibility = userVisibility ?? presentation.defaultVisibility
    }

    mutating func systemDidChangeVisibility(
        _ newVisibility: NavigationSplitViewVisibility,
        presentation: ConsoleSplitPresentation
    ) {
        // A callback from a different layout must not pin the outgoing column state.
        guard presentation.hasUsableSize, presentation == appliedPresentation else { return }
        switch newVisibility {
        case .all, .doubleColumn: reportedSidebarVisibility = true
        case .detailOnly: reportedSidebarVisibility = false
        default: reportedSidebarVisibility = nil
        }
        let changed = visibility != newVisibility
        visibility = newVisibility
        // Automatic is a policy, not a report that the sidebar is visible.
        // Compact stack navigation also must not become a regular-width preference.
        if changed, presentation.usesRegularColumns, reportedSidebarVisibility != nil {
            userVisibility = newVisibility
        }
    }

    mutating func toggleSidebar() {
        let next: NavigationSplitViewVisibility = reportedSidebarVisibility == true ? .detailOnly : .all
        userVisibility = next
        visibility = next
    }
}
