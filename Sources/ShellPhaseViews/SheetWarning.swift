//
//  SheetWarning.swift
//  Role: a problem said inside a sheet or a pane: a warning glyph and the sentence in primary text, so it never rests on colour
//        alone (the sheet's counterpart of ShellInspector's `InspectorWarning`).
//

import SwiftUI

public struct SheetWarning: View {
    let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Label {
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .accessibilityElement(children: .combine)
    }
}
