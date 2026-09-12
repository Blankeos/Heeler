import Foundation
import GameController
import Testing

@testable import Heeler

@MainActor
@Suite("Hardware keyboard monitor")
struct HardwareKeyboardMonitorTests {
    @Test func stubHoldsTheInjectedAttachment() {
        let attached = HardwareKeyboardMonitor.stub(attached: true)
        let detached = HardwareKeyboardMonitor.stub(attached: false)
        #expect(attached.isHardwareKeyboardAttached)
        #expect(!detached.isHardwareKeyboardAttached)
    }

    @Test func connectAndDisconnectNotificationsFollowTheCoalescedProbe() {
        var present = false
        let center = NotificationCenter()
        let monitor = HardwareKeyboardMonitor(
            isHardwareKeyboardAttached: false,
            notificationCenter: center,
            coalescedKeyboardPresent: { present })
        #expect(!monitor.isHardwareKeyboardAttached)

        present = true
        center.post(name: .GCKeyboardDidConnect, object: nil)
        #expect(monitor.isHardwareKeyboardAttached)

        present = false
        center.post(name: .GCKeyboardDidDisconnect, object: nil)
        #expect(!monitor.isHardwareKeyboardAttached)
    }
}
