import Foundation
import GhosttyTerminal
import Testing
import UIKit

@testable import Heeler

/// Stage Manager live resize changes a window's size on consecutive frames.
/// Every grid the Host hears is a full TUI redraw, so a burst must reach the
/// Host as one PTY resize carrying the grid the window settled on.
@Suite("Terminal window resize coalescing")
struct TerminalWindowResizeCoalescingTests {
    @Test func theFirstLayoutOnlyEstablishesTheBaseline() {
        var tracker = TerminalWindowResizeTracker()

        let first = tracker.windowDidLayout(size: CGSize(width: 1024, height: 768))
        let repeated = tracker.windowDidLayout(size: CGSize(width: 1024, height: 768))
        #expect(!first)
        #expect(!repeated)
    }

    @Test func onlyAChangedWindowSizeCounts() {
        var tracker = TerminalWindowResizeTracker()
        _ = tracker.windowDidLayout(size: CGSize(width: 1024, height: 768))

        let narrower = tracker.windowDidLayout(size: CGSize(width: 900, height: 768))
        let smaller = tracker.windowDidLayout(size: CGSize(width: 880, height: 760))
        // A layout pass for any other reason — the keyboard, a split-view
        // column — leaves the window's size alone.
        let unchanged = tracker.windowDidLayout(size: CGSize(width: 880, height: 760))
        #expect(narrower)
        #expect(smaller)
        #expect(!unchanged)
    }

    /// The choke point itself: N grid reports inside one freeze leave as one
    /// resize, the last one.
    @MainActor
    @Test func aBurstOfGridReportsForwardsOnlyTheFinalGrid() async throws {
        var reportedGrids: [TerminalGridSize] = []
        let bridge = TerminalSessionCallbackBridge(
            onSizeChanged: { columns, rows in
                reportedGrids.append(TerminalGridSize(columns: columns, rows: rows))
            },
            onViewportTextChanged: nil,
            onSend: nil,
            onScroll: nil,
            onPaste: nil)
        let phases = TerminalGridReportPhaseRecorder(observing: bridge)

        bridge.beginSizeReportDeferral()
        for step in 0..<12 {
            bridge.resize(
                InMemoryTerminalViewport(columns: UInt16(120 - step), rows: UInt16(40 - step)))
        }
        bridge.finishSizeReportDeferral()

        let forwarded = try await phases.thawedGrid()
        #expect(forwarded == TerminalGridSize(columns: 109, rows: 29))
        #expect(reportedGrids == [TerminalGridSize(columns: 109, rows: 29)])
    }

    /// The trigger, on a real surface: resizing the window several times in
    /// a row holds every grid report, then thaws once with the grid the
    /// surface settled on.
    @MainActor
    @Test func aLiveWindowResizeReportsOnlyTheSettledGrid() async throws {
        var reportedGrids: [TerminalGridSize] = []
        let terminal = TerminalScreenView.makeConfiguredTerminal(
            onSizeChanged: { columns, rows in
                reportedGrids.append(TerminalGridSize(columns: columns, rows: rows))
            },
            notificationCenter: NotificationCenter())
        terminal.frame = CGRect(x: 0, y: 0, width: 834, height: 1100)
        let controller = UIViewController()
        controller.view = terminal
        let window = try await makeTestWindow(
            frame: terminal.bounds,
            rootViewController: controller)
        defer { window.isHidden = true }
        try await waitForGhosttyContentLayer(in: terminal)
        terminal.layoutIfNeeded()
        // Let the first layout's own reports land before the burst starts.
        try await Task.sleep(for: .milliseconds(300))
        reportedGrids.removeAll()

        // A layout pass that leaves the window's size alone is not a resize.
        terminal.setNeedsLayout()
        terminal.layoutIfNeeded()
        #expect(terminal.gridReportPhase == .live)

        let phases = TerminalGridReportPhaseRecorder(observing: terminal)
        for step in 1...6 {
            window.frame = CGRect(
                x: 0, y: 0,
                width: 834 - CGFloat(step) * 40,
                height: 1100 - CGFloat(step) * 80)
            window.layoutIfNeeded()
            #expect(terminal.gridReportPhase == .deferring)
        }
        #expect(reportedGrids.isEmpty, "a grid reached the Host mid-resize: \(reportedGrids)")

        let forwarded = try await phases.thawedGrid()
        // Anything still in Ghostty's pipeline gets the chance to leak out.
        try await Task.sleep(for: .milliseconds(300))
        #expect(forwarded == terminal.measuredGrid)
        #expect(
            reportedGrids.count <= 1,
            "the burst reached the Host as \(reportedGrids)")
        if let forwarded {
            #expect(reportedGrids.allSatisfy { $0 == forwarded })
        }
    }

    /// Keyboard notifications are process-wide. Only the window that owns
    /// the keyboard measures it; another window of the app leaves its
    /// terminal's inset alone (#157).
    @Test func onlyTheKeyWindowOwnsTheKeyboard() {
        #expect(
            TerminalKeyboardInset.windowOwnsKeyboard(
                isKeyWindow: true, isSceneKeyWindow: true, activationState: .foregroundActive))
        #expect(
            !TerminalKeyboardInset.windowOwnsKeyboard(
                isKeyWindow: false, isSceneKeyWindow: true, activationState: .foregroundActive))
        #expect(
            !TerminalKeyboardInset.windowOwnsKeyboard(
                isKeyWindow: false, isSceneKeyWindow: false, activationState: .foregroundActive))
    }

    /// UIKit restores the keyboard while a scene is still foregrounding, and
    /// no window is key yet; the scene's own key window stands in there.
    @Test func aForegroundingSceneMeasuresThroughItsOwnKeyWindow() {
        #expect(
            TerminalKeyboardInset.windowOwnsKeyboard(
                isKeyWindow: false, isSceneKeyWindow: true, activationState: .foregroundInactive))
        #expect(
            !TerminalKeyboardInset.windowOwnsKeyboard(
                isKeyWindow: false, isSceneKeyWindow: false, activationState: .foregroundInactive))
        #expect(
            !TerminalKeyboardInset.windowOwnsKeyboard(
                isKeyWindow: true, isSceneKeyWindow: true, activationState: .background))
    }
}
