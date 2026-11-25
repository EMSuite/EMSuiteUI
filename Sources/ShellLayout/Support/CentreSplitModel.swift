import Foundation

/// The arithmetic of a room's centre (`WorkspaceCentre`): one panel, or two side by side with one divider between them
/// (EMSuiteUI#261). No SwiftUI, so a test holds every number the view draws with.
///
/// The fraction is the leading panel's share of the usable width (the centre's width less the divider's line). It is
/// stored per window under the room's key and clamped where it is drawn, so a fraction saved in a wide window still
/// leaves both panels their floor in a narrow one. With the two floors equal the clamp is `PaneSplit`'s own
/// (`PaneSplit.smallestFraction`), which is what `WorkspaceCentre` draws through.
public nonisolated struct CentreSplitModel: Equatable, Sendable {
    /// One panel filling the centre, or two with a divider.
    public enum Arrangement: Equatable, Sendable {
        case single
        case split
    }

    public let arrangement: Arrangement
    /// Where the divider sits before the person moves it, and where a double click on it puts it back.
    public let defaultFraction: Double
    /// Neither panel is driven under its floor while there is room for both (HIG, split views: "Set reasonable
    /// defaults for minimum and maximum pane sizes"). Below the two floors together the centre is halved.
    public let minimumLeading: CGFloat
    public let minimumTrailing: CGFloat

    /// - Parameter defaultFraction: A share in 0...1; a value outside is pulled in, and one that is not a number is 0.5.
    public init(
        arrangement: Arrangement = .split,
        defaultFraction: Double = 0.5,
        minimumLeading: CGFloat = LayoutPolicy.imagePaneMinimum,
        minimumTrailing: CGFloat = LayoutPolicy.imagePaneMinimum
    ) {
        self.arrangement = arrangement
        self.defaultFraction = defaultFraction.isFinite ? min(max(defaultFraction, 0), 1) : 0.5
        self.minimumLeading = max(minimumLeading, 0)
        self.minimumTrailing = max(minimumTrailing, 0)
    }

    /// A single panel has no divider to drag, reset or reach by keyboard.
    public var hasDivider: Bool { arrangement == .split }

    /// The leading panel's smallest and largest share of `usable` points. Below the two floors together both bounds
    /// are 0.5: there is no arrangement that honours both, so the centre divides what it has evenly.
    public func bounds(usable: CGFloat) -> ClosedRange<Double> {
        guard usable > 0, usable > minimumLeading + minimumTrailing else { return 0.5...0.5 }
        return Double(minimumLeading / usable)...Double(1 - minimumTrailing / usable)
    }

    /// `fraction` held inside `bounds(usable:)`; a fraction that is not a number becomes the default first.
    public func clamped(_ fraction: Double, usable: CGFloat) -> Double {
        let range = bounds(usable: usable)
        let value = fraction.isFinite ? fraction : defaultFraction
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// The fraction a window starts from: what it stored, or the default when it stored nothing (or nothing usable).
    public func restored(_ stored: Double?) -> Double {
        guard let stored, stored.isFinite, (0...1).contains(stored) else { return defaultFraction }
        return stored
    }

    /// What a double click on the divider (or VoiceOver's reset action) sets.
    public var resetFraction: Double { defaultFraction }

    /// The two panels' widths in a centre `total` points wide: the divider's line is taken out first, the leading
    /// width is rounded to a whole point and the trailing one takes the rest. A single panel takes the whole width.
    public func widths(fraction: Double, total: CGFloat) -> (leading: CGFloat, trailing: CGFloat) {
        guard hasDivider else { return (max(total, 0), 0) }
        let usable = max(total - LayoutPolicy.sciencePaneDividerWidth, 1)
        let leading = (usable * CGFloat(clamped(fraction, usable: usable))).rounded()
        return (leading, usable - leading)
    }

    /// The scene-storage key of a room's divider: one per room, so each centre remembers its own split
    /// (`"workspace.centre.edx.fraction"` for the room `edx`).
    public static func storageKey(room: String) -> String {
        "workspace.centre.\(room).fraction"
    }
}
