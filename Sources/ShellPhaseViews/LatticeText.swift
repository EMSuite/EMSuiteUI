//
//  LatticeText.swift
//  Role: how the phase views write a cell, once for the Add Phase preview and My Phases: lengths to four decimals in Å,
//        angles to two in degrees. It takes plain numbers, so a kit structure's cell and a stored snapshot's cell read alike.
//

import Foundation

enum LatticeText {
    /// "4.0782, 4.0782, 4.0782 Å".
    nonisolated static func lengths(_ a: Double, _ b: Double, _ c: Double) -> String {
        String(format: "%.4f, %.4f, %.4f Å", a, b, c)
    }

    /// "90.00°, 90.00°, 120.00°".
    nonisolated static func angles(_ alpha: Double, _ beta: Double, _ gamma: Double) -> String {
        String(format: "%.2f°, %.2f°, %.2f°", alpha, beta, gamma)
    }
}
