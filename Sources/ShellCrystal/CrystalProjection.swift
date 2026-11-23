//
//  CrystalProjection.swift
//  Role: where each atom lands on the pane, computed by the view itself from the same numbers the camera uses (parallel
//        projection, the scene's bounding sphere framed on the shorter side), not by RealityKit hit testing (design 5.4). The hover
//        chip picks the front-most atom under the pointer with it, and the element symbols drawn under Differentiate Without Color
//        sit where it says. Also the one rule for how an orientation set from outside is shown: a spin, or a crossfade under
//        Reduce Motion.
//

import CoreGraphics
import simd

/// The parallel projection of the crystal view, in SwiftUI points (origin top left, y down).
public nonisolated struct CrystalProjection: Sendable {
    public let size: CGSize
    let rotation: simd_double3x3
    let centre: SIMD3<Double>
    /// Points per Å.
    public let scale: Double

    /// The projection the view draws with: the scene's bounding sphere, with the camera's margin, fills the shorter side.
    public init(scene: CrystalScene, orientation: simd_double3x3, size: CGSize) {
        self.size = size
        self.rotation = CrystalTurn.viewRotation(orientation)
        self.centre = scene.centre
        let halfHeightAngstrom = scene.boundingRadius * Self.margin
        let aspect = Double(size.width / max(size.height, 1))
        // RealityKit's orthographic scale is the half-height; for a tall pane it is widened so the sphere fits the width.
        let halfHeight = aspect >= 1 ? halfHeightAngstrom : halfHeightAngstrom / max(aspect, 0.1)
        self.scale = Double(size.height) / 2 / halfHeight
    }

    /// The camera's margin around the bounding sphere (`CrystalEntities.orthographicScale`).
    public static let margin = 1.08

    /// The screen point of a crystal position, and its depth in Å towards the viewer.
    public func project(_ position: SIMD3<Double>) -> (point: CGPoint, depth: Double) {
        let v = rotation * (position - centre)
        return (CGPoint(x: Double(size.width) / 2 + v.x * scale, y: Double(size.height) / 2 - v.y * scale), v.z)
    }

    /// The front-most atom whose drawn ball covers `point`, or nil. A ball smaller than `minimumReach` points is picked within
    /// that reach, so small atoms stay easy to hover.
    public func atom(at point: CGPoint, in scene: CrystalScene, minimumReach: Double = 5) -> Int? {
        var best: (index: Int, depth: Double)?
        for (i, atom) in scene.atoms.enumerated() {
            let p = project(atom.position)
            let reach = max(CrystalElements.ballRadius(z: atom.atomicNumber) * scale, minimumReach)
            let dx = Double(p.point.x - point.x), dy = Double(p.point.y - point.y)
            guard dx * dx + dy * dy <= reach * reach else { continue }
            if best == nil || p.depth > best!.depth { best = (i, p.depth) }
        }
        return best?.index
    }

    /// The atoms whose centres face the viewer unhidden enough to carry a label: drawn back to front, and an atom is skipped when a
    /// nearer atom's ball covers its centre. At most `limit` labels, nearest first.
    public func labelledAtoms(in scene: CrystalScene, limit: Int = 300) -> [(index: Int, point: CGPoint)] {
        let projected = scene.atoms.enumerated().map { (i, a) in (i, project(a.position), CrystalElements.ballRadius(z: a.atomicNumber) * scale) }
        let nearestFirst = projected.sorted { $0.1.depth > $1.1.depth }
        var shown: [(index: Int, point: CGPoint, radius: Double)] = []
        for (i, p, r) in nearestFirst {
            let covered = shown.contains { s in
                let dx = Double(s.point.x - p.point.x), dy = Double(s.point.y - p.point.y)
                return dx * dx + dy * dy < s.radius * s.radius * 0.8
            }
            if !covered { shown.append((i, p.point, r)) }
            if shown.count == limit { break }
        }
        return shown.map { (index: $0.index, point: $0.point) }
    }
}

/// How the view shows an orientation that changed from outside (a typed zone axis, Return to Zone Axis, Index).
public nonisolated enum CrystalMotion: Equatable, Sendable {
    /// Set at once: a drag, a key step or a small change.
    case none
    /// Turns to it over `CrystalMotion.duration`.
    case spin
    /// Fades through, under Reduce Motion.
    case crossfade

    /// Changes smaller than this are set at once (a key step is 1°).
    public static let threshold = 5 * Double.pi / 180
    /// The spin's and the crossfade's length in seconds.
    public static let duration = 0.35

    public static func transition(from old: simd_double3x3, to new: simd_double3x3, dragging: Bool, reduceMotion: Bool) -> CrystalMotion {
        guard !dragging, CrystalTurn.angle(from: old, to: new) >= threshold else { return .none }
        return reduceMotion ? .crossfade : .spin
    }
}
