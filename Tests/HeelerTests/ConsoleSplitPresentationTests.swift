import SwiftUI
import Testing

@testable import Heeler

@Suite("Console split presentation")
struct ConsoleSplitPresentationTests {
    private let landscape = ConsoleSplitPresentation(
        horizontalSizeClass: .regular, size: CGSize(width: 1194, height: 834))
    private let portrait = ConsoleSplitPresentation(
        horizontalSizeClass: .regular, size: CGSize(width: 834, height: 1194))

    @Test func regularLandscapeShowsBothColumns() {
        #expect(landscape.defaultVisibility == .all)
        #expect(landscape.showsSidebarToggle)
        #expect(landscape.sidebarWidth == .init(minimum: 320, ideal: 380, maximum: 440))
    }

    @Test func regularPortraitShowsDetail() {
        #expect(portrait.defaultVisibility == .detailOnly)
        #expect(portrait.showsSidebarToggle)
        #expect(portrait.sidebarWidth == .init(minimum: 320, ideal: 380, maximum: 400))
    }

    @Test(arguments: [false, true])
    func compactRetainsAutomaticVisibility(isLandscape: Bool) {
        let presentation = ConsoleSplitPresentation(
            horizontalSizeClass: .compact,
            size: isLandscape ? CGSize(width: 844, height: 390) : CGSize(width: 390, height: 844))
        #expect(presentation.defaultVisibility == .automatic)
        #expect(!presentation.showsSidebarToggle)
        #expect(presentation.sidebarWidth == .init(minimum: 320, ideal: 380, maximum: nil))
    }

    @Test func unknownSizeClassUsesAutomaticVisibility() {
        let presentation = ConsoleSplitPresentation(
            horizontalSizeClass: nil, size: CGSize(width: 1194, height: 834))
        #expect(presentation.defaultVisibility == .automatic)
        #expect(!presentation.showsSidebarToggle)
    }

    @Test func squareWindowShowsDetail() {
        let presentation = ConsoleSplitPresentation(
            horizontalSizeClass: .regular, size: CGSize(width: 900, height: 900))
        #expect(presentation.defaultVisibility == .detailOnly)
    }

    @Test func safeAreaInsetsPreservePortraitAspectWithKeyboard() {
        let presentation = ConsoleSplitPresentation(
            horizontalSizeClass: .regular, size: CGSize(width: 834, height: 700),
            safeAreaInsets: EdgeInsets(top: 24, leading: 0, bottom: 470, trailing: 0))
        #expect(presentation.defaultVisibility == .detailOnly)
    }

    @Test func portraitSeedFollowsRotationUntilUserToggles() {
        var state = ConsoleSplitVisibilityState()
        state.update(from: portrait)
        #expect(state.visibility == .detailOnly)
        state.update(from: landscape)
        #expect(state.visibility == .all)
        state.update(from: portrait)
        #expect(state.visibility == .detailOnly)
        #expect(state.userVisibility == nil)
    }

    @Test func compactSeedFollowsRegularWidthLayout() {
        var state = ConsoleSplitVisibilityState()
        state.update(from: ConsoleSplitPresentation(
            horizontalSizeClass: .compact, size: CGSize(width: 390, height: 844)))
        #expect(state.visibility == .automatic)
        state.update(from: landscape)
        #expect(state.visibility == .all)
        state.update(from: portrait)
        #expect(state.visibility == .detailOnly)
    }

    @Test(arguments: [false, true])
    func explicitToggleSurvivesRotationAndSystemWriteBacks(startInPortrait: Bool) {
        var state = ConsoleSplitVisibilityState()
        state.update(from: startInPortrait ? portrait : landscape)
        state.toggleSidebar()
        let chosen: NavigationSplitViewVisibility = startInPortrait ? .all : .detailOnly
        #expect(state.visibility == chosen)
        #expect(state.userVisibility == chosen)
        state.update(from: startInPortrait ? landscape : portrait)
        #expect(state.visibility == chosen)
        state.update(from: ConsoleSplitPresentation(
            horizontalSizeClass: .compact, size: CGSize(width: 390, height: 844)))
        state.systemDidChangeVisibility(.automatic)
        #expect(state.userVisibility == chosen)
        state.update(from: landscape)
        #expect(state.visibility == chosen)
        state.update(from: portrait)
        #expect(state.visibility == chosen)
    }

    @Test func systemWriteBackDoesNotBecomeAUserToggle() {
        var state = ConsoleSplitVisibilityState()
        state.systemDidChangeVisibility(.detailOnly)
        state.update(from: landscape)
        #expect(state.visibility == .all)
        state.systemDidChangeVisibility(.all)
        state.update(from: portrait)
        #expect(state.visibility == .detailOnly)
        #expect(state.userVisibility == nil)
    }

    @Test func sidebarButtonCanReverseAnExplicitChoice() {
        var state = ConsoleSplitVisibilityState()
        state.update(from: portrait)
        #expect(state.sidebarToggleTitle == "Show Sidebar")
        state.toggleSidebar()
        #expect(state.sidebarToggleTitle == "Hide Sidebar")
        state.toggleSidebar()
        state.update(from: landscape)
        #expect(state.visibility == .detailOnly)
        #expect(state.userVisibility == .detailOnly)
    }

    @Test(arguments: [CGSize.zero, CGSize(width: 0, height: 834), CGSize(width: 1194, height: 0)])
    func zeroSizedPassDoesNotSeedOrReplaceLayout(size: CGSize) {
        let invalid = ConsoleSplitPresentation(
            horizontalSizeClass: .regular, size: size,
            safeAreaInsets: EdgeInsets(top: 24, leading: 20, bottom: 20, trailing: 20))
        #expect(!invalid.hasUsableSize)
        var state = ConsoleSplitVisibilityState()
        state.update(from: invalid)
        #expect(state.visibility == .automatic)
        #expect(state.userVisibility == nil)
        state.update(from: landscape)
        #expect(state.visibility == .all)
        state.update(from: invalid)
        #expect(state.visibility == .all)
    }
}
