import SwiftUI

/// Resolve against the presenting Console, since a form may itself be compact.
enum ConsoleSheetPresentation: Equatable {
    case form
    case largeSheet

    init(horizontalSizeClass: UserInterfaceSizeClass?) {
        self = horizontalSizeClass == .regular ? .form : .largeSheet
    }
}

struct ConsoleSheetPresentationModifier: ViewModifier {
    let presentation: ConsoleSheetPresentation

    @ViewBuilder
    func body(content: Content) -> some View {
        switch presentation {
        case .form:
            content.presentationSizing(.form)
        case .largeSheet:
            // These three destinations used the default large sheet at the base revision.
            content.presentationDetents([.large])
        }
    }
}
