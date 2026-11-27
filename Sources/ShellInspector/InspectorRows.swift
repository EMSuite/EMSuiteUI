import ShellControls
import SwiftUI

/// The inspector's row vocabulary — one kit for every room (owner rule): a
/// layout fix belongs here, never hand-rolled in a room file.
///
/// Built to Apple's own inspector guidance: a `Form` "renders as a vertical
/// stack" on macOS, not boxed cards, so sections are flat — a title with a
/// LEADING disclosure triangle (HIG, Disclosure controls), rows, a hairline;
/// status colour lives on symbols, text stays in the system label colours
/// (HIG, Labels/Color); at most one prominent button per view (HIG, Buttons)
/// and that one is the room's verb in the toolbar, so every inspector button
/// is a plain bordered push button; buttons in a set share one width
/// (`.buttonSizing(.flexible)`); controls `.regular`. One alignment rule, the
/// owner's (Pixelmator's): label leading, control or value at the trailing
/// edge. Presentation only — no `AppState`, `OperationCenter` or `Session`
/// reference here, and no number that isn't an `InspectorMetrics` constant or one
/// of this file's own, explained constants.

/// The numbers this file's rows own (they equal the `LayoutPolicy` values the apps' room files still read).
enum InspectorMetrics {
    /// Between the rows of a section (`LayoutPolicy.inspectorRowSpacing`).
    static let rowSpacing: CGFloat = 6
    /// Above and below a section's content, inside its hairlines.
    static let sectionPadding: CGFloat = 8
    /// The value field above an adjustment slider (`LayoutPolicy.adjustmentValueWidth`).
    static let adjustmentValueWidth: CGFloat = 64
    /// A numeric field in a row (`LayoutPolicy.numericFieldWidth`).
    static let numericFieldWidth: CGFloat = 72
}

/// The room or tab an `InspectorSection` renders in.
///
/// A section remembers its own expansion by title alone unless scoped —
/// which left unrelated sections that happen to share a title ("Dataset" in
/// the Info tab and "Dataset" among the Settings tab's own actions, "Result"
/// in two rooms) collapsing together, since they wrote the same
/// `@SceneStorage` key. `WorkspaceInspector` sets this once per tab ("info"),
/// and `WorkspaceSettings` again, more specifically, per task's room file
/// within the Settings tab ("settings.map", "settings.phase", …), so the key
/// each section remembers its state under is scoped to where it actually
/// lives. Default "" so a section built outside that scaffolding (a preview,
/// a test) still gets a stable, if unscoped, key.
private struct InspectorScopeKey: EnvironmentKey {
    static let defaultValue: String = ""
}

/// How a section opens and closes: a short ease, or none while Reduce Motion is on (HIG, Motion: honour the
/// setting wherever motion is not the point; here it is only a courtesy). A pure function so a test can hold it.
nonisolated enum InspectorSectionMotion {
    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.15)
    }
}

extension EnvironmentValues {
    public var inspectorScope: String {
        get { self[InspectorScopeKey.self] }
        set { self[InspectorScopeKey.self] = newValue }
    }
}

/// A collapsible group of inspector rows — the pane's basic unit.
///
/// The whole title row is the disclosure control (the owner: "disclosure on
/// the label, not the chevron"), with the triangle at the leading edge where
/// macOS puts it. A hairline closes each section. When the caller passes no
/// `expanded` binding, the section remembers its own state, scoped by
/// `inspectorScope` and title, via `@SceneStorage`; until the person opens or
/// closes it, it is open, or closed when `startsExpanded` is false (Export).
/// With an `expanded` binding the caller owns the state and `startsExpanded` is not read.
///
/// `icon` and `emphasized` serve the one header that needs more: a parallax
/// stage row, bolder while it is the active step. `statusGlyph` is drawn at the
/// trailing edge of the title row (a stage's state, always visible, also when
/// closed); it is decoration only: VoiceOver hears `status`.
public struct InspectorSection<Content: View>: View {
    private let header: InspectorSectionHeader
    private let startsExpanded: Bool
    private let externalExpanded: Binding<Bool>?
    private let content: Content
    @Environment(\.inspectorScope) private var scope

    public init(
        _ title: String,
        icon: Image? = nil,
        emphasized: Bool = false,
        status: String? = nil,
        statusGlyph: Image? = nil,
        startsExpanded: Bool = true,
        expanded: Binding<Bool>? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.header = InspectorSectionHeader(title: title, icon: icon, emphasized: emphasized, status: status, statusGlyph: statusGlyph)
        self.startsExpanded = startsExpanded
        self.externalExpanded = expanded
        self.content = content()
    }

    /// The `@SceneStorage` key a title-only section (no `expanded:` binding)
    /// remembers its own state under. A `static func`, not inline in `body`,
    /// so the scoping rule is testable without hosting a view.
    static func sceneStorageKey(scope: String, title: String) -> String {
        "inspector.section.\(scope).\(title)"
    }

    public var body: some View {
        if let externalExpanded {
            InspectorSectionBody(header: header, isExpanded: externalExpanded, content: content)
        } else {
            InspectorSectionRemembering(
                key: Self.sceneStorageKey(scope: scope, title: header.title),
                startsExpanded: startsExpanded, header: header, content: content)
        }
    }
}

/// What a section's title row shows and speaks.
struct InspectorSectionHeader {
    let title: String
    let icon: Image?
    let emphasized: Bool
    /// Spoken with the header ("Complete" on a finished stage); never drawn as text.
    let status: String?
    /// Drawn at the trailing edge; hidden from VoiceOver (it hears `status`).
    let statusGlyph: Image?

    /// What VoiceOver reads as the header's value: the status, then open or closed. The glyph adds nothing to it.
    func spokenValue(expanded: Bool) -> String {
        RoomAccessibilityText.sectionHeaderValue(status: status, expanded: expanded)
    }
}

/// Owns the `@SceneStorage` for a section with no explicit `expanded:`
/// binding.
///
/// Split out from `InspectorSection` because the storage key needs
/// `inspectorScope`, an `@Environment` value — not yet readable inside
/// `InspectorSection`'s own `init`, before it is attached to the view
/// hierarchy, so it is resolved in `InspectorSection.body` instead (where
/// `@Environment` reads are ordinary) and handed to this view as a plain
/// `init` parameter, where `@SceneStorage` can use it immediately. With no
/// stored value the section opens as `startsExpanded` says.
private struct InspectorSectionRemembering<Content: View>: View {
    private let header: InspectorSectionHeader
    @SceneStorage private var isExpanded: Bool
    private let content: Content

    init(key: String, startsExpanded: Bool, header: InspectorSectionHeader, content: Content) {
        self.header = header
        self._isExpanded = SceneStorage(wrappedValue: startsExpanded, key)
        self.content = content
    }

    var body: some View {
        InspectorSectionBody(header: header, isExpanded: $isExpanded, content: content)
    }
}

/// The section's chrome, shared by the remembered-state and explicit-binding
/// paths: a title row that is itself the disclosure control, the rows, a
/// hairline. Collapsed, only the title row and the hairline remain.
private struct InspectorSectionBody<Content: View>: View {
    let header: InspectorSectionHeader
    let isExpanded: Binding<Bool>
    let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            title
            if isExpanded.wrappedValue {
                VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
                    content
                }
                .padding(.top, InspectorMetrics.sectionPadding)
            }
        }
        .padding(.vertical, InspectorMetrics.sectionPadding)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var title: some View {
        Button {
            withAnimation(InspectorSectionMotion.animation(reduceMotion: reduceMotion)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                    .accessibilityHidden(true)
                if let icon = header.icon {
                    icon
                        .foregroundStyle(header.emphasized ? .primary : .secondary)
                        .accessibilityHidden(true)
                }
                Text(header.title)
                    .font(.headline.weight(header.emphasized ? .bold : .semibold))
                Spacer(minLength: 0)
                if let glyph = header.statusGlyph {
                    glyph
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(header.spokenValue(expanded: isExpanded.wrappedValue))
    }
}

/// A non-collapsible run of rows — no title, no disclosure, no
/// `@SceneStorage` — for content that never had a name of its own (a room's
/// mode switch, a matcher's run button). Same rhythm and hairline as
/// `InspectorSection`.
public struct InspectorGroup<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
            content
        }
        .padding(.vertical, InspectorMetrics.sectionPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// One labelled control: the label at the leading edge in the primary label
/// colour, the control at the trailing edge — the owner's one alignment rule
/// (Pixelmator: "label left, control right, value at the edge"). The label
/// is one line at its own width, never compressed; the control takes what
/// is left and adapts. No fixed label column. Hiding a control's own label is the caller's
/// job. `emphasized` sets the label semibold (a ranked list's top row).
public struct InspectorRow<Content: View>: View {
    private let label: String
    private let emphasized: Bool
    private let content: Content
    /// Pairs the label with the control, so VoiceOver reads the control by the row's label (EMSuiteUI#126).
    @Namespace private var pair

    public init(_ label: String, emphasized: Bool = false, @ViewBuilder content: () -> Content) {
        self.label = label
        self.emphasized = emphasized
        self.content = content()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            // One line, never compressed: with the control given priority
            // the label wrapped to one character per line ("Pr / es / et")
            // when this shared a fixed width with the control. Labels are
            // short by design; the control adapts instead (`ViewThatFits`,
            // compressing pickers).
            Text(label)
                .fontWeight(emphasized ? .semibold : .regular)
                .fixedSize()
                .accessibilityLabeledPair(role: .label, id: "row", in: pair)
            Spacer(minLength: 0)
            content
                .accessibilityLabeledPair(role: .content, id: "row", in: pair)
        }
        .controlSize(.regular)
    }
}

/// An on/off in a row (control-placement §3: "An on/off is a switch in a row; a checkbox only inside a list"): the row's
/// title at the leading edge, a switch at the trailing edge with its own label hidden, the title its accessibility label.
/// Both apps drew this by hand (`Aperture ☐ Objective aperture`, the noun twice); this is the one shape (EMSuiteUI#253).
public struct InspectorSwitchRow: View {
    /// The row's words: drawn once, at the leading edge, and the switch's spoken name.
    public let title: String
    private let isOn: Binding<Bool>

    public init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self.isOn = isOn
    }

    public var body: some View {
        InspectorRow(title) {
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel(title)
        }
    }
}

/// A read-only fact: label leading, the value trailing in the secondary
/// label colour, selectable (a value the reader may paste into a notebook)
/// and in monospaced digits so a column of these keeps its numerals aligned.
/// `mono` sets the whole value monospaced — a path or a shape string.
///
/// On one line when label and value fit side by side; otherwise the label
/// takes its own line and the value wraps, trailing-aligned, beneath it (as
/// Xcode's inspectors do). Info labels are often DATA — a provenance key such
/// as "relative_reference_minimum_radius_px" — and a fixed-size row raised
/// the inspector's minimum past its column and aborted the app at a 915-pt
/// window. The stacked form
/// keeps the row's minimum width at a few characters WHATEVER the value
/// says, so a live value (the scan position) can never move the inspector's
/// minimum — the constraint-loop shape. Squeezing both onto one line failed
/// on screen twice (2026-09-30): a long key left "3.92" one character wide,
/// and an even split cut short values in half.
public struct InspectorValueRow: View {
    private let label: String
    private let value: String
    private let mono: Bool

    public init(_ label: String, _ value: String, mono: Bool = false) {
        self.label = label
        self.value = value
        self.mono = mono
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label)
                    .fixedSize()
                Spacer(minLength: 0)
                // Ahead of the spacer, or the row splits evenly and a value
                // that fits is cut in half (2026-09-30 drive).
                valueText
                    .layoutPriority(1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(label)
                valueText
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var valueText: some View {
        // Mono rows carry provenance: a 17-digit decimal prints rounded, the
        // exact text on hover.
        let shown = mono ? ProvenanceValueText.display(value) : value
        return Text(shown)
            .help(mono ? value : "")
            // Identifiers and provenance values stay on one line (middle
            // truncation keeps both ends); the full text is on hover.
            .lineLimit(mono ? 1 : nil)
            .truncationMode(.middle)
            .monospacedDigit()
            .fontDesign(mono ? .monospaced : .default)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
            .selectableText(shown)
    }
}

/// The adjustment row: the label and an editable value (with an optional
/// unit) on one line, a filling `Slider` below.
///
/// The `TextField` above the slider is `InspectorMetrics.adjustmentValueWidth`
/// wide and shares the slider's binding; a typed value commits on Enter
/// (`.onSubmit`) or on focus loss, and either way is clamped into `range`
/// before it reaches `value` — never while the field is still being typed
/// in, so a value mid-edit (e.g. a bare "-" before more digits follow) is
/// not fought over. The clamp itself is `AdjustmentSlider.clamp(_:to:)`, a
/// pure static function so it can be unit-tested without hosting a view.
/// Double-clicking the label resets `value` to `defaultValue` (also
/// clamped) when one was given; with no `defaultValue` the label is inert.
public struct AdjustmentSlider: View {
    private let label: String
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double?
    private let format: FloatingPointFormatStyle<Double>
    private let unit: String?
    private let defaultValue: Double?

    public init(
        _ label: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double? = nil,
        format: FloatingPointFormatStyle<Double> = .number.precision(.fractionLength(2)),
        unit: String? = nil,
        defaultValue: Double? = nil
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.step = step
        self.format = format
        self.unit = unit
        self.defaultValue = defaultValue
    }

    public var body: some View {
        // Two lines, as Photos' Adjust panel does: label left and the
        // value at the edge (the one alignment rule), the slider below at
        // full width. A slider beside a fixed label column squeezed to
        // ~40 pt in a 280-pt popover.
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                labelView
                Spacer(minLength: 0)
                NumberEntryField(title: label, value: value, format: format) {
                    if let typed = $0 { value = Self.clamp(typed, to: range) }
                }
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: InspectorMetrics.adjustmentValueWidth)
                if let unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            slider
                .labelsHidden()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(Text(value, format: format))
        // The combined element is not the slider: it takes the slider's increment and decrement
        // itself (VoiceOver's VO-Up/Down, the Accessibility Keyboard), one step or a tenth of
        // the range at a time (EMSuiteUI#126).
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = Self.nudged(value, up: true, step: step, in: range)
            case .decrement: value = Self.nudged(value, up: false, step: step, in: range)
            @unknown default: break
            }
        }
        // Double-clicking the label was the only way to reset; this is the
        // same reset for VoiceOver and the keyboard. Present only when there
        // is a default to reset to.
        .modifier(ResetActionModifier(isOffered: defaultValue != nil, reset: resetToDefault))
    }

    /// One accessibility increment or decrement: by `step` when the slider has one, else by a
    /// tenth of the range (the system slider's own increment), clamped into `range`. Pure, so a
    /// test holds it.
    static func nudged(_ value: Double, up: Bool, step: Double?, in range: ClosedRange<Double>) -> Double {
        let by = step.flatMap { $0 > 0 ? $0 : nil } ?? (range.upperBound - range.lowerBound) / 10
        return clamp(value + (up ? by : -by), to: range)
    }

    @ViewBuilder
    private var labelView: some View {
        let text = Text(label)
            .fixedSize()
            .onTapGesture(count: 2, perform: resetToDefault)
        if defaultValue != nil {
            text.help("Double-click to reset")
        } else {
            text
        }
    }

    @ViewBuilder
    private var slider: some View {
        if let step {
            Slider(value: $value, in: range, step: step)
        } else {
            Slider(value: $value, in: range)
        }
    }

    private func resetToDefault() {
        guard let defaultValue else { return }
        value = Self.clamp(defaultValue, to: range)
    }

    /// Pure on purpose: the only place a typed value can land outside
    /// `range` (the slider itself cannot), so it is the one piece of this
    /// view worth testing without hosting it.
    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

/// "Reset to default" as an accessibility action, attached only when offered.
private struct ResetActionModifier: ViewModifier {
    let isOffered: Bool
    let reset: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isOffered {
            content.accessibilityAction(named: "Reset to default", reset)
        } else {
            content
        }
    }
}

/// A one-line secondary caption under a row — the vocabulary's replacement
/// for a bare `Text(...).font(.caption).foregroundStyle(.secondary)`. Wraps
/// rather than truncating, since it is explanatory prose, not a value.
public struct InspectorNote: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A section's buttons: one row at one shared width, spanning the section
/// (`.buttonSizing(.flexible)`, macOS 26+) — HIG, Buttons: "Use style — not
/// size" to distinguish a choice, so buttons in a set match. When the row
/// cannot hold them side by side it stacks them, still full width. A lone
/// button spans the section too, never parked at one edge.
public struct InspectorActionRow<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    // One layout over the buttons, not a `ViewThatFits` of a row and a column: there each arrangement held its own copy of the buttons, so
    // a width flip swapped copies and an open popover or dialog a button owns closed (MacEMUI#158).
    public var body: some View {
        InspectorActionRowLayout(spacing: InspectorMetrics.rowSpacing) {
            content
        }
        .buttonSizing(.flexible)
        .controlSize(.regular)
        .frame(maxWidth: .infinity)
    }
}

/// The action row's buttons side by side while their ideal widths fit, else stacked full width. Side by side, every button gets an equal
/// share of the row, but never less than its own ideal width (the wider keep theirs, the rest share what is left), so a label is never cut.
struct InspectorActionRowLayout: Layout {
    var spacing: CGFloat

    /// The widths of buttons of ideal widths `ideal` side by side in `width`; nil when they do not fit (stack them). Pure, so a test holds it.
    static func rowWidths(ideal: [CGFloat], width: CGFloat?, spacing: CGFloat) -> [CGFloat]? {
        let gaps = spacing * CGFloat(max(ideal.count - 1, 0))
        let total = ideal.reduce(0, +) + gaps
        guard let width, width.isFinite else { return ideal }
        guard total <= width else { return nil }
        var widths = ideal, fixed = Set<Int>()
        // Water-filling: a button wider than the equal share keeps its ideal width; the others split what is left, until none is wider.
        while true {
            let free = ideal.indices.filter { !fixed.contains($0) }
            guard !free.isEmpty else { return widths }
            let share = (width - gaps - fixed.reduce(0) { $0 + ideal[$1] }) / CGFloat(free.count)
            let wider = free.filter { ideal[$0] > share }
            if wider.isEmpty {
                for i in free { widths[i] = share }
                return widths
            }
            fixed.formUnion(wider)
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }
        if let widths = Self.rowWidths(ideal: ideal, width: proposal.width, spacing: spacing) {
            let height = zip(subviews, widths).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
            return CGSize(width: widths.reduce(0, +) + spacing * CGFloat(max(widths.count - 1, 0)), height: height)
        }
        let width = proposal.width ?? (ideal.max() ?? 0)
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(heights.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }
        if let widths = Self.rowWidths(ideal: ideal, width: bounds.width, spacing: spacing) {
            var x = bounds.minX
            for (view, width) in zip(subviews, widths) {
                view.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: width, height: nil))
                x += width + spacing
            }
            return
        }
        var y = bounds.minY
        for view in subviews {
            let proposal = ProposedViewSize(width: bounds.width, height: nil)
            view.place(at: CGPoint(x: bounds.minX, y: y), proposal: proposal)
            y += view.sizeThatFits(proposal).height + spacing
        }
    }
}

/// A section action that never truncates: a pull-down whose label is the full
/// `Label` when the row has room and the symbol alone when it does not, with
/// the title kept on `.help` and as the accessibility label. `ViewThatFits` is
/// the durable pattern for this, not a stopgap. A button twin of the same
/// rule (mac4DSTEM's `InspectorAdaptiveButton`) sizes alike in one
/// `InspectorActionRow`. The caller adds its own accessibility identifier.
public struct InspectorAdaptiveMenu<Content: View>: View {
    private let title: String
    private let systemImage: String
    private let help: String?
    private let content: Content

    public init(
        _ title: String,
        systemImage: String,
        help: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.help = help
        self.content = content()
    }

    public var body: some View {
        Menu {
            content
        } label: {
            ViewThatFits(in: .horizontal) {
                Label(title, systemImage: systemImage)
                Image(systemName: systemImage)
            }
        }
        .buttonStyle(.glass)   // Liquid Glass like Xcode's buttons (owner 2026-10-07); the toolbar verb is `.glassProminent`
        .help(help ?? title)
        .accessibilityLabel(title)
        .accessibilityHint(RoomAccessibilityText.briefHint(from: help))
    }
}

/// A warning note: a caption-size `Label` whose SYMBOL carries the colour and whose sentence stays in the primary
/// label colour, as Prepare's calibration verdict does (HIG, Color and Labels: colour is never the sole carrier of meaning, and a whole orange sentence
/// reads poorly in either appearance and under an accent colour; the owner's rule since 2026-09-22). Named once so
/// no room hand-rolls it. Wraps like any `Label`; the symbol defaults to the filled triangle and a note whose
/// meaning is not "beware" (a refusal, a stale result) passes its own. A failure passes `tint: .red` and its own
/// symbol.
public struct InspectorWarning: View {
    private let text: String
    private let systemImage: String
    private let tint: Color
    private let font: Font

    /// `font` is `.caption` for a note under a row; a requirement's own title row passes `.subheadline`.
    public init(_ text: String, systemImage: String = "exclamationmark.triangle.fill", tint: Color = .orange,
                font: Font = .caption) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
        self.font = font
    }

    public var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(tint)
        }
        .font(font)
    }
}

// MARK: - Optional number entry

/// A numeric field for a value that may be unset: empty shows `prompt`, and an
/// emptied field commits nothing — the value in effect stays (an emptied
/// or unparsed entry must never clear a calibration the file supplied).
public struct OptionalNumericField<Value: Equatable, Format: ParseableFormatStyle>: View
where Format.FormatInput == Value, Format.FormatOutput == String {
    let title: String
    let value: Value?
    let format: Format
    var unit: String?
    var prompt: String
    let onCommit: (Value) -> Void

    public init(
        title: String,
        value: Value?,
        format: Format,
        unit: String? = nil,
        prompt: String = "Not set",
        onCommit: @escaping (Value) -> Void
    ) {
        self.title = title
        self.value = value
        self.format = format
        self.unit = unit
        self.prompt = prompt
        self.onCommit = onCommit
    }

    public var body: some View {
        HStack(spacing: 6) {
            NumberEntryField(title: title, value: value, format: format, prompt: prompt) {
                if let entered = $0 { onCommit(entered) }
            }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: InspectorMetrics.numericFieldWidth)
                // The unit is spoken with the field (see NumericFieldSpeech).
                .accessibilityLabel(NumericFieldSpeech.label(title, unit: unit))
            if let unit {
                Text(unit)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .accessibilityHidden(true)
            }
        }
    }
}
