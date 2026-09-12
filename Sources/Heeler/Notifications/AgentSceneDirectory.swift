import Foundation
import SwiftUI

/// What the deep-link policy needs to know about one connected window.
struct AgentSceneState: Equatable, Sendable {
    let id: UUID
    /// The Agent the window shows, or is waiting to show once its pane syncs.
    let presentedAgent: ConsoleAgent.ID?
    /// Higher is more recent; zero for a window that has never been active.
    let activationOrder: UInt64
}

/// Where one deep link lands.
enum AgentDeepLinkDecision: Equatable, Sendable {
    /// A window already shows the target: bring that window forward.
    case activate(sceneID: UUID)
    /// No window shows it: navigate this one, the key window.
    case route(sceneID: UUID)
    /// No window is connected yet (a killed-state launch); hold the link
    /// until one is.
    case awaitScene
}

/// The single-window rule for Agent Notification taps, Live Activity links,
/// in-app banners, and dragged rows, as a pure decision. A deep link never
/// opens a second window: an Agent already on screen is activated where it
/// is, and anything else lands in the key window. A second window on the
/// same Agent would also contend for the Host's one terminal channel.
enum AgentDeepLinkPolicy {
    static func decide(
        target: ConsoleAgent.ID?,
        scenes: [AgentSceneState],
        preferredSceneID: UUID?
    ) -> AgentDeepLinkDecision {
        guard !scenes.isEmpty else { return .awaitScene }
        if let target,
            let presenting = presentingScene(
                for: target, in: scenes, preferredSceneID: preferredSceneID)
        {
            return .activate(sceneID: presenting)
        }
        if let preferredSceneID, scenes.contains(where: { $0.id == preferredSceneID }) {
            return .route(sceneID: preferredSceneID)
        }
        return keyScene(in: scenes).map { .route(sceneID: $0) } ?? .awaitScene
    }

    /// The window already showing `agent`, preferring `preferredSceneID`
    /// and then the most recently active one if, unexpectedly, several do.
    static func presentingScene(
        for agent: ConsoleAgent.ID,
        in scenes: [AgentSceneState],
        preferredSceneID: UUID?
    ) -> UUID? {
        let presenting = scenes.filter { $0.presentedAgent == agent }
        if let preferredSceneID, presenting.contains(where: { $0.id == preferredSceneID }) {
            return preferredSceneID
        }
        return keyScene(in: presenting)
    }

    /// The most recently activated window; the first connected one breaks
    /// ties, so the answer is stable before any window has been active.
    static func keyScene(in scenes: [AgentSceneState]) -> UUID? {
        var best: AgentSceneState?
        for scene in scenes {
            if let current = best, scene.activationOrder <= current.activationOrder { continue }
            best = scene
        }
        return best?.id
    }
}

/// The app-wide registry of connected windows and the one place deep links
/// enter. Each window owns its own `AgentNotificationRouter`; this directory
/// decides which of those routers a link drives, through
/// `AgentDeepLinkPolicy`, and brings that window forward.
@MainActor
final class AgentSceneDirectory {
    private struct Entry {
        let router: AgentNotificationRouter
        let activate: @MainActor () -> Void
        var activationOrder: UInt64 = 0
    }

    private var entries: [UUID: Entry] = [:]
    /// Connection order, so iteration and tie-breaks are deterministic.
    private var order: [UUID] = []
    private var activationClock: UInt64 = 0
    /// A link that arrived before any window connected. The inner optional
    /// is the link itself: nil means "the Console".
    private var pendingOpen: AgentNotificationTarget??

    init() {}

    /// Connects a window. `activate` brings it forward when a link picks it;
    /// it must be a no-op for a window that is already frontmost.
    func register(
        sceneID: UUID,
        router: AgentNotificationRouter,
        activate: @escaping @MainActor () -> Void
    ) {
        let activationOrder = entries[sceneID]?.activationOrder ?? 0
        entries[sceneID] = Entry(
            router: router, activate: activate, activationOrder: activationOrder)
        if !order.contains(sceneID) {
            order.append(sceneID)
        }
        if let pending = pendingOpen {
            pendingOpen = nil
            open(pending, preferredSceneID: sceneID)
        }
    }

    func unregister(sceneID: UUID) {
        entries[sceneID] = nil
        order.removeAll { $0 == sceneID }
    }

    /// Records that a window became the active one, which makes it the key
    /// window for links that no window is already showing.
    func sceneDidBecomeActive(sceneID: UUID) {
        guard entries[sceneID] != nil else { return }
        activationClock &+= 1
        entries[sceneID]?.activationOrder = activationClock
    }

    var scenes: [AgentSceneState] {
        order.compactMap { id in
            guard let entry = entries[id] else { return nil }
            return AgentSceneState(
                id: id,
                presentedAgent: entry.router.path.last ?? entry.router.pendingTarget?.agentID,
                activationOrder: entry.activationOrder)
        }
    }

    /// What the key window shows; the in-app banner suppresses itself for it.
    var keyScenePresentedAgent: ConsoleAgent.ID? {
        let scenes = scenes
        guard let key = AgentDeepLinkPolicy.keyScene(in: scenes) else { return nil }
        return scenes.first(where: { $0.id == key })?.presentedAgent
    }

    /// Routes one deep link under the single-window rule. `preferredSceneID`
    /// is the window the link arrived through, when there is one — a banner
    /// tap, a URL opened into that window.
    func open(_ target: AgentNotificationTarget?, preferredSceneID: UUID? = nil) {
        let decision = AgentDeepLinkPolicy.decide(
            target: target?.agentID, scenes: scenes, preferredSceneID: preferredSceneID)
        switch decision {
        case .awaitScene:
            pendingOpen = .some(target)
        case .activate(let sceneID), .route(let sceneID):
            pendingOpen = nil
            guard let entry = entries[sceneID] else { return }
            entry.router.open(target)
            entry.activate()
        }
    }

    /// Brings forward the window already showing `agent`. False when none
    /// does, so the caller can open a new window instead.
    func activateScene(presenting agent: ConsoleAgent.ID) -> Bool {
        guard
            let sceneID = AgentDeepLinkPolicy.presentingScene(
                for: agent, in: scenes, preferredSceneID: nil),
            let entry = entries[sceneID]
        else { return false }
        entry.activate()
        return true
    }
}

/// The window-aware way into a window's navigation, provided to its Console
/// by the scene root. Links raised inside a window — a banner tap, Open in
/// New Window — still obey the single-window rule, with that window as the
/// preferred landing spot.
struct AgentSceneRouting: Equatable {
    let directory: AgentSceneDirectory
    let sceneID: UUID

    static func == (lhs: AgentSceneRouting, rhs: AgentSceneRouting) -> Bool {
        lhs.directory === rhs.directory && lhs.sceneID == rhs.sceneID
    }

    @MainActor
    func open(_ target: AgentNotificationTarget?) {
        directory.open(target, preferredSceneID: sceneID)
    }
}

extension EnvironmentValues {
    /// Nil outside a scene root (previews, hosted test views, the screenshot
    /// mode), where the Console drives its own router directly.
    @Entry var agentSceneRouting: AgentSceneRouting? = nil
}
