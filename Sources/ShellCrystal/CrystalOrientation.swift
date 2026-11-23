//
//  CrystalOrientation.swift
//  Role: the one orientation convention of the crystal view, and the turns a drag, a key or a VoiceOver action makes.
//        The orientation is a 3 by 3 matrix in py4DSTEM's convention, the same value DiffractoKit's CrystalOrientation holds: its
//        columns are the lab (view) x, y and z axes written in the crystal's Cartesian frame, z from the sample towards the source,
//        so the beam runs along -z, into the screen. A crystal vector v therefore appears on screen at Mᵀv: x right, y up, z out of
//        the screen. The camera never moves; the crystal turns. Pattern and crystal share this value, so they cannot disagree.
//        The view only reports turns: snapping to a zone axis and naming the nearest one belong to the app's document.
//

import simd

/// Turns of the crystal view, all about the view's own axes (screen right, screen up, towards the viewer).
public nonisolated enum CrystalTurn {
    /// The key and VoiceOver step: 1°.
    public static let stepAngle = Double.pi / 180

    /// Drag sensitivity: radians per point of pointer travel (400 pt turn the crystal by 180°).
    public static let radiansPerPoint = Double.pi / 400

    /// The crystal-to-view rotation of an orientation matrix: Mᵀ.
    public static func viewRotation(_ orientation: simd_double3x3) -> simd_double3x3 { orientation.transpose }

    /// The orientation after the crystal turns by `rotation`, written in view axes: M' = M Rᵀ, so that M'ᵀ = R Mᵀ.
    public static func turned(_ orientation: simd_double3x3, by rotation: simd_double3x3) -> simd_double3x3 {
        orientation * rotation.transpose
    }

    /// A rotation by `angle` about the view axis `axis` (unit length).
    public static func rotation(angle: Double, axis: SIMD3<Double>) -> simd_double3x3 {
        simd_double3x3(simd_quatd(angle: angle, axis: simd_normalize(axis)))
    }

    /// The turn of a drag by `translation` points (SwiftUI: x right, y down). A plain drag tilts: right turns the near side of the
    /// crystal to the right (about view y), down turns it down (about view x). With ⌥ the drag rotates in the plane about the beam:
    /// right turns the crystal clockwise as seen on screen.
    public static func drag(translation: SIMD2<Double>, rotatesInPlane: Bool) -> simd_double3x3 {
        let k = radiansPerPoint
        if rotatesInPlane { return rotation(angle: -translation.x * k, axis: [0, 0, 1]) }
        let yaw = rotation(angle: translation.x * k, axis: [0, 1, 0])
        let pitch = rotation(angle: translation.y * k, axis: [1, 0, 0])
        return yaw * pitch
    }

    /// The turn of one key press or VoiceOver action.
    public static func step(_ direction: CrystalTurnDirection, angle: Double = stepAngle) -> simd_double3x3 {
        switch direction {
        case .tiltLeft: rotation(angle: -angle, axis: [0, 1, 0])
        case .tiltRight: rotation(angle: angle, axis: [0, 1, 0])
        case .tiltUp: rotation(angle: -angle, axis: [1, 0, 0])
        case .tiltDown: rotation(angle: angle, axis: [1, 0, 0])
        case .rotateClockwise: rotation(angle: -angle, axis: [0, 0, 1])
        case .rotateCounterclockwise: rotation(angle: angle, axis: [0, 0, 1])
        }
    }

    /// The orientation that looks down the zone axis `uvw` (a crystal direction in Cartesian Å, e.g. `cell * [u, v, w]`), with the
    /// crystal direction `up` as close to screen up as it can be. For tests and previews; the app takes the orientation from its document.
    public static func lookingDown(_ uvw: SIMD3<Double>, up: SIMD3<Double>) -> simd_double3x3 {
        let z = simd_normalize(uvw)
        var y = up - simd_dot(up, z) * z
        if simd_length(y) < 1e-9 {
            y = simd_cross(z, abs(z.x) < 0.9 ? [1, 0, 0] : [0, 1, 0])
        }
        y = simd_normalize(y)
        let x = simd_cross(y, z)
        return simd_double3x3(columns: (x, y, z))
    }

    /// The angle in radians between two orientations (the size of the turn from one to the other).
    public static func angle(from a: simd_double3x3, to b: simd_double3x3) -> Double {
        let r = a.transpose * b
        let trace = r.columns.0.x + r.columns.1.y + r.columns.2.z
        return acos(min(1, max(-1, (trace - 1) / 2)))
    }

    /// The nearest proper rotation to `m` (re-orthonormalised), so many small turns never let the matrix drift.
    public static func orthonormalized(_ m: simd_double3x3) -> simd_double3x3 {
        simd_double3x3(simd_normalize(simd_quatd(m)))
    }
}

/// The named turns of the arrow keys and VoiceOver.
public nonisolated enum CrystalTurnDirection: String, CaseIterable, Sendable {
    case tiltLeft, tiltRight, tiltUp, tiltDown, rotateClockwise, rotateCounterclockwise

    /// The VoiceOver action's name.
    public var actionName: String {
        switch self {
        case .tiltLeft: "Tilt Left"
        case .tiltRight: "Tilt Right"
        case .tiltUp: "Tilt Up"
        case .tiltDown: "Tilt Down"
        case .rotateClockwise: "Rotate Clockwise"
        case .rotateCounterclockwise: "Rotate Counterclockwise"
        }
    }
}

/// A change of orientation the view reports. `isFinal` is false while a drag is in progress (transient view state that may drive
/// the pattern each frame) and true when the drag ends or for a key press or an action: the moment the app writes it to its
/// document, with undo.
public nonisolated struct CrystalOrientationChange: Equatable, Sendable {
    public var orientation: simd_double3x3
    public var isFinal: Bool
    public init(orientation: simd_double3x3, isFinal: Bool) { self.orientation = orientation; self.isFinal = isFinal }
}
