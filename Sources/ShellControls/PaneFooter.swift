import SwiftUI

// MARK: - Pane footer

/// The bottom overlay row of an image pane: the scale bar at the leading edge,
/// the colour legend at the trailing edge.
///
/// On a tall, narrow pane there is not enough width for both: the legend is
/// 146pt wide before its label, and the bar is quantized to ~70pt of *drawn*
/// length plus its own caption, so a collision is a property of the width of
/// the **drawn image box** — `LayoutPolicy.fitted(in:aspect:)`, which this
/// overlay sits inside — and NOT of the pane. For a square pattern in a pane
/// taller than it is wide the two coincide; for a rotated tall-narrow scan
/// the box stays narrow at any divider position, so that pane is stacked
/// always and correctly.
///
/// Side by side while both ideal widths fit, stacked otherwise (`PaneFooterLayout`), which keeps the wide case pixel-identical to what
/// shipped and makes the narrow case legible instead of overlapping. One layout over the same two views, not a `ViewThatFits` of two
/// arrangements: there each arrangement held its own copy of the views, so a width flip (a zoom changes the bar's length) swapped copies
/// and the legend chip's open popover closed (MacEMUI#158).
public struct PaneFooter<Leading: View, Trailing: View>: View {
    private let leading: Leading
    private let trailing: Trailing

    public init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        PaneFooterLayout {
            HStack(alignment: .bottom, spacing: 8) { leading }
            HStack(spacing: 0) { trailing }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

/// The footer's two views, leading then trailing. Side by side (bottoms aligned, the leading at the left, the trailing at the right, at
/// least `spacing` apart) when their ideal widths fit the width offered; else stacked, the trailing above at the right, `stackSpacing`
/// above the leading at the left: the legend is the taller, fixed-width block, so stacking it on top keeps the bar against the pane's
/// bottom-left corner where it sits in the wide case.
struct PaneFooterLayout: Layout {
    static let spacing: CGFloat = 8
    static let stackSpacing: CGFloat = 6

    /// Where each view goes in a footer `width` wide (nil: the views' own width) for views of ideal sizes `leading` and `trailing`:
    /// the footer's size and each view's origin (top-left). Pure, so a test holds it.
    struct Placement: Equatable {
        var size: CGSize
        var leading: CGPoint
        var trailing: CGPoint
        var stacked: Bool
    }

    static func placement(width: CGFloat?, leading l: CGSize, trailing t: CGSize) -> Placement {
        let sideWidth = l.width + spacing + t.width
        let available = width.flatMap { $0.isFinite ? $0 : nil }
        if available.map({ sideWidth <= $0 }) ?? true {
            let w = available ?? sideWidth, h = max(l.height, t.height)
            return Placement(size: CGSize(width: w, height: h), leading: CGPoint(x: 0, y: h - l.height),
                             trailing: CGPoint(x: w - t.width, y: h - t.height), stacked: false)
        }
        let w = available ?? max(l.width, t.width), h = t.height + stackSpacing + l.height
        return Placement(size: CGSize(width: w, height: h), leading: CGPoint(x: 0, y: t.height + stackSpacing),
                         trailing: CGPoint(x: w - t.width, y: 0), stacked: true)
    }

    private func ideal(_ subviews: Subviews, _ index: Int) -> CGSize {
        subviews.indices.contains(index) ? subviews[index].sizeThatFits(.unspecified) : .zero
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        Self.placement(width: proposal.width, leading: ideal(subviews, 0), trailing: ideal(subviews, 1)).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let l = ideal(subviews, 0), t = ideal(subviews, 1)
        let p = Self.placement(width: bounds.width, leading: l, trailing: t)
        let origin = CGPoint(x: bounds.minX, y: bounds.maxY - p.size.height)
        if subviews.indices.contains(0) {
            subviews[0].place(at: CGPoint(x: origin.x + p.leading.x, y: origin.y + p.leading.y), proposal: ProposedViewSize(l))
        }
        if subviews.indices.contains(1) {
            subviews[1].place(at: CGPoint(x: origin.x + p.trailing.x, y: origin.y + p.trailing.y), proposal: ProposedViewSize(t))
        }
    }
}
