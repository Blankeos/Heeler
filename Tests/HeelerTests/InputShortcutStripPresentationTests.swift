import Foundation
import Testing

@testable import Heeler

@Suite("Input shortcut strip presentation")
struct InputShortcutStripPresentationTests {
    @Test func compactSoftwareKeyboardKeepsTodaysFullSetAndScrolls() {
        let presentation = InputShortcutStripPresentation(
            hardwareKeyboardAttached: false, sizeClass: .compact)
        #expect(presentation.items == InputShortcutStripPresentation.softwareKeyboardItems)
        #expect(presentation.usesHorizontalScroll)
        #expect(presentation.leadingItems == [
            .key(.escape), .key(.tab), .key(.shiftTab),
            .key(.up), .key(.down), .key(.left), .key(.right),
            .key(.backspace), .key(.shiftEnter), .paste,
        ])
        #expect(presentation.trailingItems == [.key(.enter), .more])
    }

    @Test func regularSoftwareKeyboardKeepsTheFullSetWithoutScrolling() {
        let presentation = InputShortcutStripPresentation(
            hardwareKeyboardAttached: false, sizeClass: .regular)
        #expect(presentation.items == InputShortcutStripPresentation.softwareKeyboardItems)
        #expect(!presentation.usesHorizontalScroll)
        #expect(presentation.trailingItems.isEmpty)
        #expect(presentation.leadingItems == presentation.items)
    }

    @Test func compactHardwareKeyboardKeepsOnlyTerminalChords() {
        let presentation = InputShortcutStripPresentation(
            hardwareKeyboardAttached: true, sizeClass: .compact)
        #expect(presentation.items == InputShortcutStripPresentation.hardwareKeyboardItems)
        #expect(!presentation.usesHorizontalScroll)
        #expect(Set(Self.hardwareProvidedKeys).isDisjoint(with: Set(presentation.items)))
    }

    @Test func regularHardwareKeyboardMatchesTheCompactHardwareSet() {
        let compact = InputShortcutStripPresentation(
            hardwareKeyboardAttached: true, sizeClass: .compact)
        let regular = InputShortcutStripPresentation(
            hardwareKeyboardAttached: true, sizeClass: .regular)
        #expect(regular.items == compact.items)
        #expect(regular.items == InputShortcutStripPresentation.hardwareKeyboardItems)
        #expect(!regular.usesHorizontalScroll)
    }

    @Test func disconnectingAHardwareKeyboardReexpandsTheCompactStrip() {
        let attached = InputShortcutStripPresentation(
            hardwareKeyboardAttached: true, sizeClass: .compact)
        let detached = InputShortcutStripPresentation(
            hardwareKeyboardAttached: false, sizeClass: .compact)
        #expect(attached.items == InputShortcutStripPresentation.hardwareKeyboardItems)
        #expect(detached.items == InputShortcutStripPresentation.softwareKeyboardItems)
        #expect(detached.usesHorizontalScroll)
        #expect(Set(Self.hardwareProvidedKeys).isSubset(of: Set(detached.items)))
        #expect(Set(Self.hardwareProvidedKeys).isDisjoint(with: Set(attached.items)))
    }

    @Test func disconnectingAHardwareKeyboardReexpandsTheRegularStrip() {
        let attached = InputShortcutStripPresentation(
            hardwareKeyboardAttached: true, sizeClass: .regular)
        let detached = InputShortcutStripPresentation(
            hardwareKeyboardAttached: false, sizeClass: .regular)
        #expect(attached.items == InputShortcutStripPresentation.hardwareKeyboardItems)
        #expect(detached.items == InputShortcutStripPresentation.softwareKeyboardItems)
        #expect(!detached.usesHorizontalScroll)
    }

    @Test func hardwareKeyboardSetIsExactlyTheTerminalOnlyChords() {
        #expect(InputShortcutStripPresentation.hardwareKeyboardItems == [
            .controlModifier,
            .optionModifier,
            .key(.shiftEnter),
            .interrupt,
            .paste,
            .more,
        ])
    }

    private static let hardwareProvidedKeys: [InputShortcutStripItem] = [
        .key(.escape), .key(.tab),
        .key(.up), .key(.down), .key(.left), .key(.right),
        .key(.backspace), .key(.enter),
    ]
}
