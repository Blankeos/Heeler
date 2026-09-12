import SwiftUI
import Testing

@testable import Heeler

@Suite("Console sheet presentation")
struct ConsoleSheetPresentationTests {
    @Test func regularWidthUsesFormSizing() {
        #expect(ConsoleSheetPresentation(horizontalSizeClass: .regular) == .form)
    }

    @Test func compactWidthKeepsLargeSheet() {
        #expect(ConsoleSheetPresentation(horizontalSizeClass: .compact) == .largeSheet)
    }

    @Test func unknownSizeClassKeepsLargeSheet() {
        #expect(ConsoleSheetPresentation(horizontalSizeClass: nil) == .largeSheet)
    }
}
