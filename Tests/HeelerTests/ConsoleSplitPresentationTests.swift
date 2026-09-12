import SwiftUI
import Testing

@testable import Heeler

@Suite("Console split presentation")
struct ConsoleSplitPresentationTests {
    @Test(arguments: [false, true])
    func regularLandscapeKeepsBothColumns(hasSelection: Bool) {
        let presentation = ConsoleSplitPresentation(
            horizontalSizeClass: .regular, size: CGSize(width: 1194, height: 834),
            hasSelection: hasSelection)
        #expect(presentation.style == .balanced)
        #expect(presentation.defaultVisibility == .all)
        #expect(presentation.sidebarWidth == .init(minimum: 320, ideal: 380, maximum: 440))
    }

    @Test(arguments: [false, true])
    func regularPortraitLeadsWithDetail(hasSelection: Bool) {
        let presentation = ConsoleSplitPresentation(
            horizontalSizeClass: .regular, size: CGSize(width: 834, height: 1194),
            hasSelection: hasSelection)
        #expect(presentation.style == .prominentDetail)
        #expect(presentation.defaultVisibility == (hasSelection ? .detailOnly : .all))
        #expect(presentation.sidebarWidth == .init(minimum: 320, ideal: 380, maximum: 400))
    }

    @Test(arguments: [false, true], [false, true])
    func compactRetainsAutomaticNavigation(isLandscape: Bool, hasSelection: Bool) {
        let presentation = ConsoleSplitPresentation(
            horizontalSizeClass: .compact,
            size: isLandscape ? CGSize(width: 844, height: 390) : CGSize(width: 390, height: 844),
            hasSelection: hasSelection)
        #expect(presentation.style == .automatic)
        #expect(presentation.defaultVisibility == .automatic)
        #expect(presentation.sidebarWidth == .init(minimum: 320, ideal: 380, maximum: nil))
    }

    @Test func unknownSizeClassUsesCompactPolicy() {
        let presentation = ConsoleSplitPresentation(
            horizontalSizeClass: nil, size: CGSize(width: 1194, height: 834), hasSelection: true)
        #expect(presentation.style == .automatic)
        #expect(presentation.defaultVisibility == .automatic)
    }

    @Test func squareWindowUsesDetailLedPolicy() {
        let presentation = ConsoleSplitPresentation(
            horizontalSizeClass: .regular, size: CGSize(width: 900, height: 900), hasSelection: false)
        #expect(presentation.style == .prominentDetail)
        #expect(presentation.defaultVisibility == .all)
    }

    @Test(arguments: [NavigationSplitViewVisibility.all, .detailOnly])
    func toggleSurvivesRotationSelectionAndSizeClassChanges(visibility: NavigationSplitViewVisibility) {
        var state = ConsoleSplitVisibilityState()
        state.seed(from: ConsoleSplitPresentation(
            horizontalSizeClass: .regular, size: CGSize(width: 1194, height: 834), hasSelection: false))
        #expect(state.visibility == .all)
        state.setVisibility(visibility)
        for sizeClass in [UserInterfaceSizeClass.regular, .compact] {
            state.seed(from: ConsoleSplitPresentation(
                horizontalSizeClass: sizeClass, size: CGSize(width: 834, height: 1194), hasSelection: true))
            #expect(state.visibility == visibility)
        }
        state.seed(from: ConsoleSplitPresentation(
            horizontalSizeClass: .regular, size: CGSize(width: 1194, height: 834), hasSelection: false))
        #expect(state.visibility == visibility)
    }

    @Test func restoredPortraitSelectionSeedsDetailOnlyOnce() {
        var state = ConsoleSplitVisibilityState()
        let presentation = ConsoleSplitPresentation(
            horizontalSizeClass: .regular, size: CGSize(width: 834, height: 1194), hasSelection: true)
        state.seed(from: presentation)
        #expect(state.visibility == .detailOnly)
        state.setVisibility(.all)
        state.seed(from: presentation)
        #expect(state.visibility == .all)
    }
}
