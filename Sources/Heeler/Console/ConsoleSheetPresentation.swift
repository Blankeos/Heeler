import SwiftUI

/// Resolve against the presenting view, since a form may itself be compact.
enum ConsoleSheetPresentation: Equatable {
    case form
    case inheritedSheet

    init(horizontalSizeClass: UserInterfaceSizeClass?) {
        self = horizontalSizeClass == .regular ? .form : .inheritedSheet
    }
}

struct ConsoleSheetPresentationModifier: ViewModifier {
    let presentation: ConsoleSheetPresentation

    @ViewBuilder
    func body(content: Content) -> some View {
        switch presentation {
        case .form:
            content.presentationSizing(.form)
        case .inheritedSheet:
            // Keep each destination's existing detents (including Rename's medium sheet).
            content
        }
    }
}
