import CoreGraphics
import Foundation

/// One control on Direct Input's shortcut strip. Views project this; they do
/// not decide which keys belong on the strip.
enum InputShortcutStripItem: Hashable, Sendable {
    case key(AgentQuickKey)
    case paste
    /// One-shot Control for the next strip key (terminal Ctrl, not the
    /// hardware keyboard's Control-as-system-modifier).
    case controlModifier
    /// One-shot Option as terminal meta/Alt.
    case optionModifier
    /// Distinct Ctrl-C interrupt. Hardware Control+C is not the same as
    /// sending that chord through Attach.
    case interrupt
    case more
}

/// Ordered shortcut-strip contents derived from hardware-keyboard attachment
/// and horizontal size class. The view must not recompute this inline.
struct InputShortcutStripPresentation: Equatable, Sendable {
    enum SizeClass: Equatable, Sendable, CaseIterable {
        case compact
        case regular
    }

    let hardwareKeyboardAttached: Bool
    let sizeClass: SizeClass
    /// Keys that scroll on compact software-keyboard layout, or the full
    /// flexible row when scrolling is off.
    let leadingItems: [InputShortcutStripItem]
    /// Pinned trailing keys (Enter + More) on compact software-keyboard layout.
    let trailingItems: [InputShortcutStripItem]
    let usesHorizontalScroll: Bool

    var items: [InputShortcutStripItem] { leadingItems + trailingItems }

    /// Today's Direct Input strip: navigation keys plus paste, Enter, More.
    static let softwareKeyboardItems: [InputShortcutStripItem] = [
        .key(.escape), .key(.tab), .key(.shiftTab),
        .key(.up), .key(.down), .key(.left), .key(.right),
        .key(.backspace), .key(.shiftEnter),
        .paste, .key(.enter), .more,
    ]

    /// Terminal-only keys a hardware keyboard does not replace: Ctrl/Alt
    /// chord entry, Shift-Enter, Ctrl-C, paste review, and Skills/Snippets.
    static let hardwareKeyboardItems: [InputShortcutStripItem] = [
        .controlModifier, .optionModifier, .key(.shiftEnter),
        .interrupt, .paste, .more,
    ]

    init(hardwareKeyboardAttached: Bool, sizeClass: SizeClass) {
        self.hardwareKeyboardAttached = hardwareKeyboardAttached
        self.sizeClass = sizeClass
        if hardwareKeyboardAttached {
            leadingItems = Self.hardwareKeyboardItems
            trailingItems = []
            usesHorizontalScroll = false
        } else if sizeClass == .compact {
            leadingItems = Array(Self.softwareKeyboardItems.dropLast(2))
            trailingItems = Array(Self.softwareKeyboardItems.suffix(2))
            usesHorizontalScroll = true
        } else {
            leadingItems = Self.softwareKeyboardItems
            trailingItems = []
            usesHorizontalScroll = false
        }
    }
}

/// Named layout constants for the five input chromes. Raw pixel widths stay
/// here so the views do not embed magic numbers.
enum InputChromeLayout {
    /// Shortcut row and its key caps. Matches the pre-iPad compact height.
    static let shortcutRowHeight: CGFloat = 44

    static let compactEscapeTabWidth: CGFloat = 38
    static let compactShiftTabWidth: CGFloat = 46
    static let compactShiftEnterWidth: CGFloat = 54
    static let compactEnterWidth: CGFloat = 42
    static let compactArrowWidth: CGFloat = 30
    /// Backspace and other wide utility caps on the compact strip.
    static let compactWideKeyWidth: CGFloat = 72
    static let compactMoreWidth: CGFloat = 44
    /// `UIPasteControl` disables itself below this side length.
    static let pasteControlSide: CGFloat = 34
    /// Visual width after scaling the paste control down to the key-cap size.
    static let pasteVisualWidth: CGFloat = 30
    static let pinnedFadeWidth: CGFloat = 8

    /// Caps a short hardware-keyboard strip so five keys do not each stretch
    /// to 200 pt on a 13-inch iPad. The group is centered; leftover space is
    /// a consequence of that cap, not a leftover iPhone well.
    static let maxFlexibleKeyWidth: CGFloat = 72

    /// Caps Terminal / Agent / Skills keyboard wells and centers them when
    /// the window is wider. A single row must not span a 1000 pt iPad.
    static let maxKeyboardContentWidth: CGFloat = 768

    /// Context-menu skill preview has no parent width. This is the card cap
    /// so a short description still reads as a card, not a 370 pt iPhone well.
    static let skillPreviewMaxWidth: CGFloat = 420

    static let shellAccessoryButtonWidth: CGFloat = 44
    /// Compact Text/Keys segmented control. Unchanged from the iPhone row.
    static let compactModePickerMaxWidth: CGFloat = 184
    /// Regular Text/Keys control. Grows for iPad but does not span the row.
    static let regularModePickerMaxWidth: CGFloat = 360

    /// Page-dot cluster on the Agent tools pager.
    static let keyboardPageIndicatorWidth: CGFloat = 15

    static func compactWidth(for key: AgentQuickKey) -> CGFloat {
        switch key {
        case .escape, .tab:
            compactEscapeTabWidth
        case .shiftTab:
            compactShiftTabWidth
        case .shiftEnter:
            compactShiftEnterWidth
        case .enter:
            compactEnterWidth
        case .left, .up, .down, .right:
            compactArrowWidth
        case .backspace, .home, .end, .pageUp, .pageDown,
            .insert, .forwardDelete, .function, .character:
            compactWideKeyWidth
        }
    }

    static func compactWidth(for item: InputShortcutStripItem) -> CGFloat {
        switch item {
        case .key(let key):
            compactWidth(for: key)
        case .paste:
            pasteVisualWidth
        case .controlModifier, .optionModifier:
            compactEscapeTabWidth
        case .interrupt:
            compactShiftEnterWidth
        case .more:
            compactMoreWidth
        }
    }

    static func modePickerMaxWidth(
        for sizeClass: InputShortcutStripPresentation.SizeClass
    ) -> CGFloat {
        switch sizeClass {
        case .compact: compactModePickerMaxWidth
        case .regular: regularModePickerMaxWidth
        }
    }
}
