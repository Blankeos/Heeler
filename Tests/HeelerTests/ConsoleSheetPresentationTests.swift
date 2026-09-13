import SwiftUI
import Testing

@testable import Heeler

@Suite("Console sheet presentation")
struct ConsoleSheetPresentationTests {
    @Test func regularWidthUsesFormSizing() {
        #expect(ConsoleSheetPresentation(horizontalSizeClass: .regular) == .form)
    }

    @Test func compactWidthPreservesDestinationSizing() {
        #expect(ConsoleSheetPresentation(horizontalSizeClass: .compact) == .inheritedSheet)
    }

    @Test func unknownSizeClassPreservesDestinationSizing() {
        #expect(ConsoleSheetPresentation(horizontalSizeClass: nil) == .inheritedSheet)
    }

    @Test func attachLinksPopoverPresentsOnlyFromTheControlThatOpenedIt() {
        let chip = AttachLinksOrigin.composerChip
        let floating = AttachLinksOrigin.floatingButton
        #expect(!chip.presents(nil))
        #expect(chip.presents(.composerChip))
        #expect(!floating.presents(.composerChip))
        #expect(floating.presents(.floatingButton))
        #expect(!chip.presents(.floatingButton))

        // A control that is not presenting cannot dismiss the other's popover.
        #expect(floating.dismissing(.composerChip) == .composerChip)
        #expect(chip.dismissing(.composerChip) == nil)
        #expect(chip.dismissing(nil) == nil)
    }
}
