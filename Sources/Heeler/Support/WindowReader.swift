import SwiftUI
import UIKit

/// Reports the `UIWindow` the modified SwiftUI subtree is mounted in.
///
/// With more than one window on iPad, "the key window of the first
/// foreground scene" is some window, not necessarily this one. Anything
/// window-scoped — safe-area insets, keyboard geometry, scene activation —
/// has to ask the view's own window instead, and SwiftUI does not expose it.
/// The callback runs synchronously from `didMoveToWindow`, before the first
/// frame is committed, so it must not mutate SwiftUI state; hand the window
/// to a reference type such as ``WindowReference`` instead.
struct WindowReader: UIViewRepresentable {
    let onWindow: (UIWindow) -> Void

    func makeUIView(context: Context) -> WindowReaderView {
        WindowReaderView(onWindow: onWindow)
    }

    func updateUIView(_ view: WindowReaderView, context: Context) {
        view.onWindow = onWindow
        if let window = view.window {
            onWindow(window)
        }
    }
}

final class WindowReaderView: UIView {
    var onWindow: (UIWindow) -> Void

    init(onWindow: @escaping (UIWindow) -> Void) {
        self.onWindow = onWindow
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let window {
            onWindow(window)
        }
    }
}

/// A weak, observable handle on one window. Views read `window` in `body`
/// the way they would read any other observable value, so a subtree that
/// renders before its window attaches renders again once it has.
@MainActor
@Observable
final class WindowReference {
    @ObservationIgnored private weak var storage: UIWindow?
    private var attachments: UInt64 = 0

    init() {}

    var window: UIWindow? {
        _ = attachments
        return storage
    }

    /// Idempotent: re-attaching the same window changes nothing.
    func attach(_ window: UIWindow) {
        guard storage !== window else { return }
        storage = window
        attachments &+= 1
    }
}

extension EnvironmentValues {
    /// The window of the scene this view belongs to, provided by the scene's
    /// root view. Nil outside a scene root (previews, hosted test views).
    @Entry var sceneWindow: WindowReference? = nil
}
