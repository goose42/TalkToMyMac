import Foundation

/// What a click (not a drag) on the floating indicator does.
public enum IndicatorClick: Equatable, Sendable {
    case openMenu
    case dismissNotice
    case togglePicker
    case none

    /// A secondary click (right-click or Control-click) always opens the menu. A primary
    /// click keeps its older meanings while a notice or replacement review is showing, and
    /// opens the menu on the plain indicator.
    public static func action(isSecondary: Bool, hasNotice: Bool, hasReview: Bool,
                              isBeforePaste: Bool) -> IndicatorClick {
        if isSecondary { return .openMenu }
        if hasNotice { return .dismissNotice }
        if hasReview { return isBeforePaste ? .none : .togglePicker }
        return .openMenu
    }
}
