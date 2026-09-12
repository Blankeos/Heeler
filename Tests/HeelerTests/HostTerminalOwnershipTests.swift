import Foundation
import Testing

@testable import Heeler

/// Which window holds a Host's one terminal channel when several windows
/// show that Host's Agents (ADR 0011, ADR 0015).
@Suite("Host terminal ownership")
struct HostTerminalOwnershipTests {
    private let hostID = UUID()
    private let otherHostID = UUID()
    private let first = UUID()
    private let second = UUID()

    private func claim(
        _ sceneID: UUID, on hostID: UUID? = nil, shell: Bool = false
    ) -> HostTerminalClaim {
        HostTerminalClaim(
            sceneID: sceneID, hostID: hostID ?? self.hostID, isShellTerminal: shell)
    }

    @Test func aLoneWindowHoldsItsHost() {
        var ownership = HostTerminalOwnership()
        let claims = [claim(first)]

        ownership.reconcile(claims: claims, keySceneID: nil)

        #expect(ownership.access(sceneID: first, hostID: hostID, claims: claims) == .holds)
    }

    /// Cross-Host windows stay fully live: each Host has its own channel.
    @Test func windowsOnDifferentHostsBothHold() {
        var ownership = HostTerminalOwnership()
        let claims = [claim(first), claim(second, on: otherHostID)]

        ownership.reconcile(claims: claims, keySceneID: second)

        #expect(ownership.access(sceneID: first, hostID: hostID, claims: claims) == .holds)
        #expect(
            ownership.access(sceneID: second, hostID: otherHostID, claims: claims) == .holds)
    }

    @Test func theKeyWindowHoldsASharedHost() {
        var ownership = HostTerminalOwnership()
        let claims = [claim(first), claim(second)]

        ownership.reconcile(claims: claims, keySceneID: second)

        #expect(ownership.holders[hostID] == second)
        #expect(ownership.access(sceneID: second, hostID: hostID, claims: claims) == .holds)
        #expect(
            ownership.access(sceneID: first, hostID: hostID, claims: claims)
                == .liveInAnotherWindow(canTakeOver: true))
    }

    @Test func becomingKeyHandsTheChannelOver() {
        var ownership = HostTerminalOwnership()
        let claims = [claim(first), claim(second)]
        ownership.reconcile(claims: claims, keySceneID: first)
        #expect(ownership.holders[hostID] == first)

        ownership.reconcile(claims: claims, keySceneID: second)
        #expect(ownership.holders[hostID] == second)

        ownership.reconcile(claims: claims, keySceneID: first)
        #expect(ownership.holders[hostID] == first)
    }

    /// A background window navigating to the same Host does not pull the
    /// channel out from under the window the user is working in.
    @Test func aBackgroundWindowTurningToTheHostWaits() {
        var ownership = HostTerminalOwnership()
        ownership.reconcile(claims: [claim(first)], keySceneID: first)

        let claims = [claim(first), claim(second)]
        ownership.reconcile(claims: claims, keySceneID: first)

        #expect(ownership.holders[hostID] == first)
        #expect(
            ownership.access(sceneID: second, hostID: hostID, claims: claims)
                == .liveInAnotherWindow(canTakeOver: true))
    }

    /// The key window turning to a Host another window holds is the user
    /// choosing to watch it here.
    @Test func theKeyWindowTurningToTheHostTakesIt() {
        var ownership = HostTerminalOwnership()
        ownership.reconcile(
            claims: [claim(first), claim(second, on: otherHostID)], keySceneID: second)
        #expect(ownership.holders[hostID] == first)

        ownership.reconcile(claims: [claim(first), claim(second)], keySceneID: second)

        #expect(ownership.holders[hostID] == second)
    }

    /// A key window on the Console, on no Agent, moves nothing.
    @Test func aKeyWindowWithoutAClaimLeavesTheHolder() {
        var ownership = HostTerminalOwnership()
        let third = UUID()
        let claims = [claim(first), claim(second)]
        ownership.reconcile(claims: claims, keySceneID: second)

        ownership.reconcile(claims: claims, keySceneID: third)

        #expect(ownership.holders[hostID] == second)
    }

    @Test func takeOverMovesTheChannelUntilTheNextKeyEdge() {
        var ownership = HostTerminalOwnership()
        let claims = [claim(first), claim(second)]
        ownership.reconcile(claims: claims, keySceneID: second)

        let tookOver = ownership.takeOver(hostID: hostID, sceneID: first, claims: claims)
        #expect(tookOver)
        #expect(ownership.holders[hostID] == first)
        // Nothing about the key window changed: the takeover stands.
        ownership.reconcile(claims: claims, keySceneID: second)
        #expect(ownership.holders[hostID] == first)

        ownership.reconcile(claims: claims, keySceneID: first)
        ownership.reconcile(claims: claims, keySceneID: second)
        #expect(ownership.holders[hostID] == second)
    }

    @Test func aWindowCannotTakeOverAHostItDoesNotShow() {
        var ownership = HostTerminalOwnership()
        let claims = [claim(first), claim(second, on: otherHostID)]
        ownership.reconcile(claims: claims, keySceneID: first)

        let tookOver = ownership.takeOver(hostID: hostID, sceneID: second, claims: claims)
        #expect(!tookOver)
        #expect(ownership.holders[hostID] == first)
    }

    /// A Shell Terminal has no rejoin path to hand over, so its window keeps
    /// the Host and the waiting window is told it cannot take it.
    @Test func aShellTerminalWindowKeepsItsHost() {
        var ownership = HostTerminalOwnership()
        let claims = [claim(first, shell: true), claim(second)]
        ownership.reconcile(claims: [claim(first, shell: true)], keySceneID: first)

        ownership.reconcile(claims: claims, keySceneID: second)

        #expect(ownership.holders[hostID] == first)
        #expect(
            ownership.access(sceneID: second, hostID: hostID, claims: claims)
                == .liveInAnotherWindow(canTakeOver: false))
        let tookOver = ownership.takeOver(hostID: hostID, sceneID: second, claims: claims)
        #expect(!tookOver)
        #expect(ownership.holders[hostID] == first)
    }

    /// The Shell Terminal closes back to the Agent: the window still holds
    /// the Host, but a key edge elsewhere can now take it.
    @Test func closingTheShellTerminalMakesTheHostTransferableAgain() {
        var ownership = HostTerminalOwnership()
        ownership.reconcile(claims: [claim(first, shell: true), claim(second)], keySceneID: first)

        let claims = [claim(first), claim(second)]
        ownership.reconcile(claims: claims, keySceneID: first)
        #expect(ownership.holders[hostID] == first)
        #expect(
            ownership.access(sceneID: second, hostID: hostID, claims: claims)
                == .liveInAnotherWindow(canTakeOver: true))

        ownership.reconcile(claims: claims, keySceneID: second)
        #expect(ownership.holders[hostID] == second)
    }

    /// The holder closes or navigates away: the waiting window gets the
    /// channel without becoming key.
    @Test func aHolderLeavingPassesTheHostOn() {
        var ownership = HostTerminalOwnership()
        ownership.reconcile(claims: [claim(first), claim(second)], keySceneID: first)

        let claims = [claim(second)]
        ownership.reconcile(claims: claims, keySceneID: first)

        #expect(ownership.holders[hostID] == second)
        #expect(ownership.access(sceneID: second, hostID: hostID, claims: claims) == .holds)
    }

    /// With no key window among the claimants, the first connected holds.
    @Test func theFirstConnectedWindowHoldsWithoutAKeyClaim() {
        var ownership = HostTerminalOwnership()
        let claims = [claim(first), claim(second)]

        ownership.reconcile(claims: claims, keySceneID: nil)

        #expect(ownership.holders[hostID] == first)
    }

    @Test func aWindowWithoutAClaimHolds() {
        var ownership = HostTerminalOwnership()
        let claims = [claim(first), claim(second)]
        ownership.reconcile(claims: claims, keySceneID: first)

        #expect(ownership.access(sceneID: UUID(), hostID: hostID, claims: claims) == .holds)
    }
}
