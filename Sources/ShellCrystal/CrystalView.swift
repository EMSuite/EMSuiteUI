//
//  CrystalView.swift
//  Role: the crystal view (plan 5.1 and 5.4; EMSuiteUI #193). The phase in 3D on a dark stage, seen down the beam with a
//        parallel projection, so the atom columns line up the way the pattern is indexed. The camera never moves; the crystal turns.
//        Plain atoms, a cell and an orientation go in; orientation changes come out (`CrystalOrientationChange`): transient while a
//        drag runs, final when it ends or for a key press or a VoiceOver action, which is when the app writes its document with undo.
//        Drawn with RealityKit in a RealityView (SceneKit is deprecated in the 26 SDKs); the spike MU0 (#192) measured it.
//        Keys: the arrows tilt by 1°, ⌥ arrows rotate in the plane. VoiceOver: one element, the app's label (phase, zone axis, tilt)
//        and this view's value (atoms per element), with a named action for every turn and Return to Zone Axis.
//        `CrystalInteraction.still` draws the same picture with no gestures and no focus: the thumbnail of the Add Phase sheet.
//

import AppKit
import RealityKit
import simd
import SwiftUI

/// Whether the view can be turned.
public enum CrystalInteraction: Sendable {
    /// Drag, ⌥ drag, arrow keys and VoiceOver actions turn the crystal.
    case interactive
    /// A picture only: no gestures, not focusable (a thumbnail).
    case still
}

/// The crystal view.
public struct CrystalView: View {
    let scene: CrystalScene
    let orientation: simd_double3x3
    let showsUnitCell: Bool
    let interaction: CrystalInteraction
    let label: String
    let onChange: (CrystalOrientationChange) -> Void
    let onReturnToZoneAxis: (() -> Void)?

    /// - Parameters:
    ///   - scene: what to draw.
    ///   - orientation: the document's orientation (py4DSTEM's convention: columns are the view x, y, z axes in the crystal frame).
    ///   - showsUnitCell: draws the cell's twelve edges.
    ///   - interaction: `.still` for a thumbnail.
    ///   - accessibilityLabel: the app's words for phase, zone axis and tilt, e.g. "Silicon, zone axis [110], tilted 2.1°".
    ///   - onReturnToZoneAxis: offered as an action and in the context menu when the app can snap back.
    ///   - onOrientationChange: every turn, transient while a drag runs and final at its end.
    public init(_ scene: CrystalScene, orientation: simd_double3x3, showsUnitCell: Bool = true,
                interaction: CrystalInteraction = .interactive, accessibilityLabel: String,
                onReturnToZoneAxis: (() -> Void)? = nil,
                onOrientationChange: @escaping (CrystalOrientationChange) -> Void = { _ in }) {
        self.scene = scene; self.orientation = orientation; self.showsUnitCell = showsUnitCell; self.interaction = interaction
        self.label = accessibilityLabel; self.onReturnToZoneAxis = onReturnToZoneAxis; self.onChange = onOrientationChange
    }

    /// The orientation while a drag runs (view state, never the document's), and where the drag started.
    @State private var live: simd_double3x3?
    @State private var dragStart: simd_double3x3?
    @Environment(\.colorSchemeContrast) private var contrast

    private var shown: simd_double3x3 { live ?? orientation }

    public var body: some View {
        GeometryReader { proxy in
            CrystalStage(scene: scene, orientation: shown, showsUnitCell: showsUnitCell,
                         increasedContrast: contrast == .increased,
                         aspect: Float(proxy.size.width / max(proxy.size.height, 1)))
        }
        .background(Color(red: CrystalPalette.stage.x, green: CrystalPalette.stage.y, blue: CrystalPalette.stage.z))
        .overlay(alignment: .bottomLeading) {
            if scene.cell != nil { CrystalTriad(cell: scene.cell!, orientation: shown).padding(10) }
        }
        .modifier(CrystalInteractionModifier(enabled: interaction == .interactive, turn: turn, drag: drag, dragEnded: dragEnded,
                                             copyImage: copyImage, returnToZoneAxis: onReturnToZoneAxis))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(CrystalDescription.value(scene, showsUnitCell: showsUnitCell))
        .accessibilityIdentifier("crystal-view")
    }

    private func turn(_ direction: CrystalTurnDirection) {
        let next = CrystalTurn.orthonormalized(CrystalTurn.turned(orientation, by: CrystalTurn.step(direction)))
        onChange(CrystalOrientationChange(orientation: next, isFinal: true))
    }

    private func drag(_ translation: CGSize, rotatesInPlane: Bool) {
        let start = dragStart ?? orientation
        if dragStart == nil { dragStart = orientation }
        let next = CrystalTurn.turned(start, by: CrystalTurn.drag(translation: [translation.width, translation.height],
                                                                   rotatesInPlane: rotatesInPlane))
        live = next
        onChange(CrystalOrientationChange(orientation: next, isFinal: false))
    }

    /// Copy Image (context menu): the picture as drawn now, 2048 pixels square, on the pasteboard.
    private func copyImage() {
        let scene = scene, orientation = shown, cell = showsUnitCell
        Task {
            guard let image = await CrystalSnapshot.image(scene, orientation: orientation, showsUnitCell: cell, pixels: 2048) else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([NSImage(cgImage: image, size: NSSize(width: image.width / 2, height: image.height / 2))])
        }
    }

    private func dragEnded() {
        if let live { onChange(CrystalOrientationChange(orientation: CrystalTurn.orthonormalized(live), isFinal: true)) }
        live = nil
        dragStart = nil
    }
}

/// The RealityKit part: builds the entity tree when the scene changes and turns the pivot when the orientation does.
private struct CrystalStage: View {
    let scene: CrystalScene
    let orientation: simd_double3x3
    let showsUnitCell: Bool
    let increasedContrast: Bool
    let aspect: Float

    @State private var holder = CrystalEntityHolder()

    var body: some View {
        RealityView { content in
            content.add(holder.anchor)
            holder.rebuild(scene, showsUnitCell: showsUnitCell, increasedContrast: increasedContrast, aspect: aspect)
            holder.turn(orientation)
        } update: { _ in
            holder.rebuild(scene, showsUnitCell: showsUnitCell, increasedContrast: increasedContrast, aspect: aspect)
            holder.turn(orientation)
        }
    }
}

/// Holds the entities between updates, so a turn moves one pivot and a new scene rebuilds once.
@MainActor
final class CrystalEntityHolder {
    let anchor = Entity()
    private var built: CrystalEntities?
    private var key: (scene: CrystalScene, cell: Bool, contrast: Bool)?
    private var cameraKey: (radius: Float, aspect: Float)?

    func rebuild(_ scene: CrystalScene, showsUnitCell: Bool, increasedContrast: Bool, aspect: Float) {
        if let key, key.scene == scene, key.cell == showsUnitCell, key.contrast == increasedContrast {
            placeCamera(aspect: aspect)
            return
        }
        key = (scene, showsUnitCell, increasedContrast)
        anchor.children.removeAll()
        cameraKey = nil
        built = try? CrystalEntities.build(scene, showsUnitCell: showsUnitCell, increasedContrast: increasedContrast)
        if let built { anchor.addChild(built.root) }
        placeCamera(aspect: aspect)
    }

    private func placeCamera(aspect: Float) {
        guard let built else { return }
        if let cameraKey, cameraKey.radius == built.radius, abs(cameraKey.aspect - aspect) < 0.001 { return }
        cameraKey = (built.radius, aspect)
        anchor.children.first(where: { $0.name == "camera" })?.removeFromParent()
        anchor.addChild(CrystalEntities.camera(radius: built.radius, aspect: aspect))
    }

    func turn(_ orientation: simd_double3x3) {
        let r = CrystalTurn.viewRotation(orientation)
        let m = simd_float3x3(columns: (SIMD3<Float>(r.columns.0), SIMD3<Float>(r.columns.1), SIMD3<Float>(r.columns.2)))
        built?.pivot.orientation = simd_normalize(simd_quatf(m))
    }
}

/// Drag, keys, context menu and VoiceOver actions, only when the view is interactive.
private struct CrystalInteractionModifier: ViewModifier {
    let enabled: Bool
    let turn: (CrystalTurnDirection) -> Void
    let drag: (CGSize, Bool) -> Void
    let dragEnded: () -> Void
    let copyImage: () -> Void
    let returnToZoneAxis: (() -> Void)?

    func body(content: Content) -> some View {
        if enabled {
            content
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 1)
                    .onChanged { drag($0.translation, NSEvent.modifierFlags.contains(.option)) }
                    .onEnded { _ in dragEnded() })
                .focusable()
                .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                    let option = press.modifiers.contains(.option)
                    switch press.key {
                    case .leftArrow: turn(option ? .rotateCounterclockwise : .tiltLeft)
                    case .rightArrow: turn(option ? .rotateClockwise : .tiltRight)
                    case .upArrow: if option { return .ignored } else { turn(.tiltUp) }
                    case .downArrow: if option { return .ignored } else { turn(.tiltDown) }
                    default: return .ignored
                    }
                    return .handled
                }
                .contextMenu {
                    Button("Copy Image", action: copyImage)
                    if let returnToZoneAxis { Button("Return to Zone Axis", action: returnToZoneAxis) }
                }
                .accessibilityAction(named: CrystalTurnDirection.tiltLeft.actionName) { turn(.tiltLeft) }
                .accessibilityAction(named: CrystalTurnDirection.tiltRight.actionName) { turn(.tiltRight) }
                .accessibilityAction(named: CrystalTurnDirection.tiltUp.actionName) { turn(.tiltUp) }
                .accessibilityAction(named: CrystalTurnDirection.tiltDown.actionName) { turn(.tiltDown) }
                .accessibilityAction(named: CrystalTurnDirection.rotateClockwise.actionName) { turn(.rotateClockwise) }
                .accessibilityAction(named: CrystalTurnDirection.rotateCounterclockwise.actionName) { turn(.rotateCounterclockwise) }
                .modifier(ReturnAction(action: returnToZoneAxis))
        } else {
            content.allowsHitTesting(false)
        }
    }
}

private struct ReturnAction: ViewModifier {
    let action: (() -> Void)?
    func body(content: Content) -> some View {
        if let action { content.accessibilityAction(named: "Return to Zone Axis", action) } else { content }
    }
}

/// The a, b, c triad in the corner: each cell vector's direction on screen, drawn in 2D so its letters stay crisp.
struct CrystalTriad: View {
    let cell: simd_double3x3
    let orientation: simd_double3x3

    var body: some View {
        let arms = CrystalTriad.arms(cell: cell, orientation: orientation)
        Canvas { context, size in
            let o = CGPoint(x: size.width / 2, y: size.height / 2)
            let length = min(size.width, size.height) / 2 - 10
            for arm in arms.sorted(by: { $0.depth < $1.depth }) {
                let tip = CGPoint(x: o.x + arm.direction.x * length, y: o.y - arm.direction.y * length)
                var path = Path(); path.move(to: o); path.addLine(to: tip)
                let colour = Color(red: CrystalPalette.cellEdge.x, green: CrystalPalette.cellEdge.y, blue: CrystalPalette.cellEdge.z)
                context.stroke(path, with: .color(colour.opacity(arm.depth < 0 ? 0.55 : 1)), lineWidth: 1.5)
                let labelPoint = CGPoint(x: o.x + arm.direction.x * (length + 7), y: o.y - arm.direction.y * (length + 7))
                context.draw(Text(arm.name).font(.callout.italic()).foregroundStyle(colour), at: labelPoint)
            }
        }
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
    }

    struct Arm { let name: String; let direction: CGPoint; let depth: Double }

    /// The screen direction (x right, y up, at most length 1) and depth of a, b and c.
    static func arms(cell: simd_double3x3, orientation: simd_double3x3) -> [Arm] {
        let r = CrystalTurn.viewRotation(orientation)
        let columns = [("a", cell.columns.0), ("b", cell.columns.1), ("c", cell.columns.2)]
        return columns.map { name, v in
            let s = r * simd_normalize(v)
            return Arm(name: name, direction: CGPoint(x: s.x, y: s.y), depth: s.z)
        }
    }
}
