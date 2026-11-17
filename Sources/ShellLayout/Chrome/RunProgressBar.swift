import SwiftUI

/// The infobar's determinate run bar: a track and a fill whose width is the progress, drawn in SwiftUI.
///
/// Not `ProgressView(value:)`: on macOS that is an `NSProgressIndicator`, which animates every change of its value. A run
/// that reports about 100 times a second restarts the animation each time, so the fill crawled behind the count beside it
/// (4DSTEM-Studio#445: the bar at about 10 % while the count read 8,316 / 8,400). This fill is not animated: it draws the
/// value it is given. A nil progress (not known yet) keeps the system's indeterminate bar, which has no value to lag.
public struct RunProgressBar: View {
    private let progress: Double?

    /// - Parameter progress: 0...1 (clamped), or nil for an indeterminate bar.
    public init(progress: Double?) {
        self.progress = progress
    }

    /// The share of the track the fill covers: the progress clamped to 0...1, 0 for a value that is not finite.
    nonisolated static func fillFraction(_ progress: Double) -> Double {
        progress.isFinite ? min(1, max(0, progress)) : 0
    }

    public var body: some View {
        if let progress {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(Color.accentColor)
                        .frame(width: proxy.size.width * Self.fillFraction(progress))
                }
            }
            .frame(height: 6)
            .transaction { $0.animation = nil }
            .accessibilityElement()
            .accessibilityAddTraits(.updatesFrequently)
        } else {
            ProgressView()
                .progressViewStyle(.linear)
        }
    }
}
