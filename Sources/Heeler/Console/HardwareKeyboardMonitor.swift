import GameController
import Observation
import SwiftUI

/// Live attachment of a hardware keyboard (Magic Keyboard, Smart Keyboard,
/// or any `GCKeyboard`). Main-actor isolated; updates come from Game
/// Controller connect/disconnect notifications, never from polling.
@MainActor
@Observable
final class HardwareKeyboardMonitor {
    private(set) var isHardwareKeyboardAttached: Bool

    @ObservationIgnored
    private let tokenBag: NotificationTokenBag
    private let coalescedKeyboardPresent: @MainActor () -> Bool

    /// Production singleton used when no monitor is injected. Created on first
    /// use from a view body (main actor).
    static let shared = HardwareKeyboardMonitor()

    /// Test and preview seam: a fixed attachment value and no notifications.
    static func stub(attached: Bool) -> HardwareKeyboardMonitor {
        HardwareKeyboardMonitor(
            isHardwareKeyboardAttached: attached,
            observesNotifications: false)
    }

    init(
        isHardwareKeyboardAttached: Bool? = nil,
        notificationCenter: NotificationCenter = .default,
        observesNotifications: Bool = true,
        coalescedKeyboardPresent: @escaping @MainActor () -> Bool = {
            GCKeyboard.coalesced != nil
        }
    ) {
        self.coalescedKeyboardPresent = coalescedKeyboardPresent
        self.isHardwareKeyboardAttached = isHardwareKeyboardAttached ?? coalescedKeyboardPresent()
        let tokenBag = NotificationTokenBag(center: notificationCenter)
        self.tokenBag = tokenBag
        guard observesNotifications else { return }
        // `queue: .main` delivers on the main queue. `assumeIsolated` is the
        // Swift 6 bridge: GameController posts these names on the main thread,
        // and tests post them from the main actor, so the hop is not a Task.
        let apply: @Sendable () -> Void = { [weak self] in
            MainActor.assumeIsolated {
                self?.applyCoalescedKeyboard()
            }
        }
        tokenBag.add(
            notificationCenter.addObserver(
                forName: .GCKeyboardDidConnect, object: nil, queue: .main
            ) { _ in apply() })
        tokenBag.add(
            notificationCenter.addObserver(
                forName: .GCKeyboardDidDisconnect, object: nil, queue: .main
            ) { _ in apply() })
    }

    private func applyCoalescedKeyboard() {
        isHardwareKeyboardAttached = coalescedKeyboardPresent()
    }
}

extension EnvironmentValues {
    /// Substitute in tests and previews. Production views fall back to
    /// ``HardwareKeyboardMonitor/shared``.
    @Entry var hardwareKeyboardMonitor: HardwareKeyboardMonitor? = nil
}

/// Observer tokens plus the center they belong to. Written during MainActor
/// init and read in `deinit` only, so the bag is a token wallet rather than
/// shared mutable UI state.
private final class NotificationTokenBag: @unchecked Sendable {
    private let center: NotificationCenter
    private var tokens: [NSObjectProtocol] = []

    init(center: NotificationCenter) {
        self.center = center
    }

    func add(_ token: NSObjectProtocol) {
        tokens.append(token)
    }

    deinit {
        tokens.forEach { center.removeObserver($0) }
    }
}
