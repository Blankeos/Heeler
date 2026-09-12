import Foundation
import Testing
import UIKit

@testable import Heeler

/// From a touch or key press in a window to the directory learning the user
/// is working there. UIKit's key window cannot say this since iOS 15 (it is
/// per scene), so the passive recognizer is the only source.
@MainActor
@Suite("Window interaction")
struct WindowInteractionTests {
    private func recognizers(on window: UIWindow) -> [WindowInteractionRecognizer] {
        (window.gestureRecognizers ?? []).compactMap { $0 as? WindowInteractionRecognizer }
    }

    /// It must never change what any control or the responder chain sees.
    @Test func theRecognizerIsPassive() {
        let recognizer = WindowInteractionRecognizer {}

        #expect(!recognizer.cancelsTouchesInView)
        #expect(!recognizer.delaysTouchesBegan)
        #expect(!recognizer.delaysTouchesEnded)
        #expect(!recognizer.canPrevent(UITapGestureRecognizer()))
        #expect(!recognizer.canBePrevented(by: UITapGestureRecognizer()))
    }

    @Test func aTouchReportsAndFailsAtOnce() {
        var interactions = 0
        let recognizer = WindowInteractionRecognizer { interactions += 1 }

        recognizer.touchesBegan([], with: UIEvent())

        #expect(interactions == 1)
        #expect(recognizer.state == .failed)
    }

    /// A hardware keyboard works in a window without touching it.
    @Test func aKeyPressReportsAndFailsAtOnce() {
        var interactions = 0
        let recognizer = WindowInteractionRecognizer { interactions += 1 }

        recognizer.pressesBegan([], with: UIPressesEvent())

        #expect(interactions == 1)
        #expect(recognizer.state == .failed)
    }

    /// The scene root asks for interaction before `WindowReader` has seen
    /// the window; the recognizer arrives with the window, exactly once.
    @Test func theRecognizerIsInstalledWhenTheWindowAttachesAndOnlyOnce() {
        let reference = WindowReference()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        reference.observeInteraction {}

        reference.attach(window)
        reference.attach(window)
        reference.observeInteraction {}

        #expect(recognizers(on: window).count == 1)
    }

    /// The whole step: an interaction in the waiting window moves the Host's
    /// terminal there, with nothing else happening in between.
    @Test func touchingTheWaitingWindowHandsItTheHost() throws {
        let directory = AgentSceneDirectory()
        let hostID = UUID()
        let waiting = UUID()
        let holding = UUID()
        let waitingRouter = AgentNotificationRouter()
        let holdingRouter = AgentNotificationRouter()
        let known = ["w1:p1", "w1:p2"].map { paneID in
            ConsoleAgent(
                hostID: hostID, hostName: "mac-studio",
                agent: Agent(.fixture(paneID: paneID)),
                workspaceLabel: nil, repositoryCheckout: nil, lastOutputSnippet: nil)
        }
        waitingRouter.agentsDidChange(known)
        holdingRouter.agentsDidChange(known)
        directory.register(sceneID: waiting, router: waitingRouter, activate: {})
        directory.register(sceneID: holding, router: holdingRouter, activate: {})
        waitingRouter.path = [ConsoleAgent.ID(hostID: hostID, paneID: "w1:p1")]
        directory.sceneRouteDidChange(sceneID: waiting)
        holdingRouter.path = [ConsoleAgent.ID(hostID: hostID, paneID: "w1:p2")]
        directory.sceneRouteDidChange(sceneID: holding)
        directory.sceneDidBecomeActive(sceneID: holding)
        try #require(
            directory.terminalAccess(sceneID: waiting, hostID: hostID)
                == .liveInAnotherWindow(canTakeOver: true))

        let reference = WindowReference()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        reference.attach(window)
        reference.observeInteraction {
            directory.sceneDidReceiveInteraction(sceneID: waiting)
        }
        let recognizer = try #require(recognizers(on: window).first)

        recognizer.touchesBegan([], with: UIEvent())

        #expect(directory.terminalAccess(sceneID: waiting, hostID: hostID) == .holds)
        #expect(
            directory.terminalAccess(sceneID: holding, hostID: hostID)
                == .liveInAnotherWindow(canTakeOver: true))
    }
}
