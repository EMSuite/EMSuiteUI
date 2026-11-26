import SwiftUI

/// A room's centre: two panels side by side with one divider the person drags, or one panel filling it (EMSuiteUI#261).
/// The window around it is the shell's — the sidebar's workspaces on the left, the inspector's tools on the right, the
/// infobar and the tabbed bottom area under it (`WorkspaceColumn`) — so every room of both apps has one frame and only
/// the panels differ.
///
/// Two panels draw through `PaneSplit`, not `HSplitView`, for the reason written there (a minimum travelling between a
/// SwiftUI-owned split and its hosted content crashed a launch). The divider's position is a fraction remembered per
/// window under `storageKey` (scene storage, as `PaneSplit` keeps it; `CentreSplitModel.storageKey(room:)` names one per
/// room), starts at `defaultFraction`, keeps both panels at least `minimumPanel` wide while there is room for both,
/// and goes back to `defaultFraction` on a double click. Tab and the arrow keys, and VoiceOver's adjust, move it as
/// `PaneSplit`'s do. Each panel is usually a `CentrePanel`.
public struct WorkspaceCentre<Leading: View, Trailing: View>: View {
    /// The centre's arithmetic; internal so a test reads which arrangement a view was built with.
    let model: CentreSplitModel
    private let storageKey: String
    private let resizeLabel: String
    private let leadingName: String
    private let leading: Leading
    private let trailing: Trailing

    /// Two panels with a divider between them.
    ///
    /// - Parameters:
    ///   - storageKey: The scene-storage slot of this centre's divider, one per room
    ///     (`CentreSplitModel.storageKey(room: "edx")`).
    ///   - defaultFraction: The leading panel's share before the person moves the divider, and after a double click on it.
    ///   - minimumPanel: Neither panel is driven below this while there is room for two of them.
    ///   - resizeLabel: The divider's VoiceOver label ("Resize the spectrum and the maps").
    ///   - leadingName: The leading panel's name in the divider's VoiceOver value ("Spectrum" reads "Spectrum 50 percent").
    public init(
        storageKey: String,
        defaultFraction: Double = 0.5,
        minimumPanel: CGFloat = LayoutPolicy.imagePaneMinimum,
        resizeLabel: String = "Resize the panels",
        leadingName: String = "Left panel",
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.model = CentreSplitModel(arrangement: .split, defaultFraction: defaultFraction,
                                      minimumLeading: minimumPanel, minimumTrailing: minimumPanel)
        self.storageKey = storageKey
        self.resizeLabel = resizeLabel
        self.leadingName = leadingName
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        if model.hasDivider {
            PaneSplit(
                storageKey: storageKey,
                resizeLabel: resizeLabel,
                leadingName: leadingName,
                minimumPane: model.minimumLeading,
                defaultFraction: model.defaultFraction,
                resetsOnDoubleClick: true
            ) {
                leading
            } trailing: {
                trailing
            }
        } else {
            leading
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension WorkspaceCentre where Trailing == EmptyView {
    /// One panel filling the centre: no divider, nothing stored.
    public init(@ViewBuilder panel: () -> Leading) {
        self.model = CentreSplitModel(arrangement: .single)
        self.storageKey = ""
        self.resizeLabel = ""
        self.leadingName = ""
        self.leading = panel()
        self.trailing = EmptyView()
    }
}

/// One panel of a room's centre: a header strip of `LayoutPolicy.paneHeaderHeight` — the title at the left, the value
/// under the pointer in the gap, the panel's display controls at the right — and the content filling the rest. The look
/// is mac4DSTEM's image panes' (`DiffractionPane`, `RealSpacePane`): headline title, caption readout in monospaced
/// digits and the secondary colour, an 8-pt inset and 6 pt between header and content, no wash of its own.
///
/// Everything in the header is one line on purpose: a wrapping title or readout would change the header's height and
/// move the picture under it, and two panels' headers at one height start their pictures at one height. The title
/// yields first (the window already names the room); the readout lives in the flexible gap as an overlay, so it adds
/// nothing to the header's ideal width and a pointer moving in never pushes the controls; the panel clips, so what
/// still does not fit stays inside it instead of overprinting the divider. None of it announces a minimum upward (the
/// constraint-loop rule in `PaneSplit`).
public struct CentrePanel<Content: View, Controls: View, Readout: View>: View {
    private let title: String
    private let content: Content
    private let controls: Controls
    private let readout: Readout

    /// - Parameters:
    ///   - title: The panel's name ("Spectrum", "Diffraction (CBED)").
    ///   - content: What the panel shows; it is given the whole space under the header.
    ///   - controls: The panel's display controls (a picker, an overlay toggle), at the header's right, small.
    ///   - readout: The value under the pointer (a `Text`); it is set in caption monospaced digits, secondary, one line.
    public init(
        title: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder controls: () -> Controls,
        @ViewBuilder readout: () -> Readout
    ) {
        self.title = title
        self.content = content()
        self.controls = controls()
        self.readout = readout()
    }

    public var body: some View {
        VStack(spacing: LayoutPolicy.centrePanelHeaderSpacing) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(LayoutPolicy.centrePanelPadding)
        .clipped()
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)
                .help(title)
                .accessibilityAddTraits(.isHeader)
            readoutSlot
            controls
                .controlSize(.small)
        }
        .frame(height: LayoutPolicy.paneHeaderHeight)
    }

    /// The header's flexible gap, holding the readout at its trailing end: it shortens, and finally disappears, before
    /// it pushes the controls.
    private var readoutSlot: some View {
        Color.clear
            .frame(minWidth: LayoutPolicy.centrePanelReadoutGap, idealWidth: LayoutPolicy.centrePanelReadoutGap, maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                readout
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .allowsHitTesting(false)
    }
}

extension CentrePanel where Controls == EmptyView, Readout == EmptyView {
    /// A panel with a title and no controls or readout.
    public init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, content: content, controls: { EmptyView() }, readout: { EmptyView() })
    }
}

extension CentrePanel where Readout == EmptyView {
    /// A panel with display controls and no pointer readout.
    public init(title: String, @ViewBuilder content: () -> Content, @ViewBuilder controls: () -> Controls) {
        self.init(title: title, content: content, controls: controls, readout: { EmptyView() })
    }
}

extension CentrePanel where Controls == EmptyView {
    /// A panel with a pointer readout and no display controls.
    public init(title: String, @ViewBuilder content: () -> Content, @ViewBuilder readout: () -> Readout) {
        self.init(title: title, content: content, controls: { EmptyView() }, readout: readout)
    }
}
