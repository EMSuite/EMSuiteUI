//
//  EDXDisplayAgentTools.swift
//  Role: The agent door's tools for how the shared EDS room draws its maps (Electron-Microscopy-Studio#672), written once here and
//        registered by both apps: read each map's colour, contrast window, gamma, histogram and percentiles and the colour mix
//        (`get_eds_display`), change them as the map's scale-bar popover and the colour mix's clicks do (`set_eds_display`), and look at
//        the maps as Maps as PNG… draws them, all or a chosen few side by side (`get_eds_figure`). Each app says how a window reaches its
//        `EDXSession` and the room's `EDXRoomState`.
//
//        The settings an agent changes are the room's own `MapAppearance`, so the person sees them at once and changes them back with
//        the same popover; the agent's colours and windows are never a quantity (design DNA 5: display aids never enter a number).
//        Colours are named: the plain primaries and the Okabe-Ito set the room's regions use (distinguishable under the common
//        colour-vision deficiencies), or #RRGGBB.
//

import Foundation
import ShellAgentDoor
import ShellEDXModel
import ShellMetal
import ShellSpectroscopy
import SpectroCore

public enum EDXDisplayAgentTools {

    /// A colour an agent names: "blue", "sky_blue", ...
    struct NamedColour {
        let name: String
        let color: RegionColor
        let colourBlindSafe: Bool
    }

    /// The plain primaries, then the Okabe-Ito set (`RegionPalette`, in its order).
    static let colours: [NamedColour] = [
        NamedColour(name: "red", color: RegionColor(red: 1, green: 0, blue: 0), colourBlindSafe: false),
        NamedColour(name: "green", color: RegionColor(red: 0, green: 1, blue: 0), colourBlindSafe: false),
        NamedColour(name: "blue", color: RegionColor(red: 0, green: 0, blue: 1), colourBlindSafe: false),
        NamedColour(name: "cyan", color: RegionColor(red: 0, green: 1, blue: 1), colourBlindSafe: false),
        NamedColour(name: "magenta", color: RegionColor(red: 1, green: 0, blue: 1), colourBlindSafe: false),
        NamedColour(name: "yellow", color: RegionColor(red: 1, green: 1, blue: 0), colourBlindSafe: false),
        NamedColour(name: "white", color: RegionColor(red: 1, green: 1, blue: 1), colourBlindSafe: false),
    ] + zip(["orange", "sky_blue", "bluish_green", "sun_yellow", "vermillion", "reddish_purple", "deep_blue", "grey"], RegionPalette.colors)
        .map { NamedColour(name: $0.0, color: $0.1, colourBlindSafe: true) }

    /// The colour a name or #RRGGBB stands for; nil when it is neither.
    static func colour(named text: String) -> RegionColor? {
        let word = text.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "_")
        if let named = colours.first(where: { $0.name == word || ($0.name == "grey" && word == "gray") }) { return named.color }
        guard word.hasPrefix("#"), word.count == 7, let value = UInt32(word.dropFirst(), radix: 16) else { return nil }
        return RegionColor(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    /// The colour's name, or #RRGGBB when it has none.
    static func name(of color: RegionColor) -> String {
        func near(_ a: RegionColor, _ b: RegionColor) -> Bool {
            abs(a.red - b.red) < 1e-6 && abs(a.green - b.green) < 1e-6 && abs(a.blue - b.blue) < 1e-6
        }
        return colours.first(where: { near($0.color, color) })?.name ?? hex(color)
    }

    /// The percentiles `get_eds_display` gives, in percent.
    static let percentiles: [Double] = [1, 2, 5, 50, 95, 98, 99]

    /// The `q`-th percentile (0...100) of the finite values, linear between ranks; nil when there are none.
    static func percentile(_ sorted: [Double], _ q: Double) -> Double? {
        guard !sorted.isEmpty else { return nil }
        let at = min(max(q, 0), 100) / 100 * Double(sorted.count - 1)
        let i = Int(at.rounded(.down)), j = min(i + 1, sorted.count - 1)
        return sorted[i] + (sorted[j] - sorted[i]) * (at - Double(i))
    }

    /// The room's tools. `room` finds a window's EDS session and the room's view state (nil: the window has none).
    public static func tools(room: @escaping (AnyObject) -> (session: EDXSession, state: EDXRoomState)?) -> [AgentTool] {
        func open(_ call: AgentToolCall) -> Result<(session: EDXSession, state: EDXRoomState), Refusal> {
            guard let windowState = call.window?.state, let found = room(windowState) else {
                return .failure(Refusal(status: 404, message: "This window has no EDS room."))
            }
            guard found.session.hasImage else {
                return .failure(Refusal(status: 404, message: "No spectrum image is open in the EDS room; open one first."))
            }
            return .success(found)
        }
        return [
            AgentTool(name: "get_eds_display", title: "EDS map display",
                      summary: "How the EDS room draws each map: its colour (an element map, black to that colour) or colormap (the scan "
                          + "image), its contrast window (low and high as fractions of the map's full scale) and gamma, whether it is in "
                          + "the colour mix, its histogram (32 bins from 0 to full scale) and percentiles (value and fraction), so a "
                          + "contrast can be chosen from the data. Also the named colours (colour_blind_safe marks the Okabe-Ito set) "
                          + "and the colormaps set_eds_display takes.",
                      input: .window) { call in
                switch open(call) {
                case .failure(let refusal): return refusal.output
                case .success(let r): return .json(display(r.session, r.state))
                }
            },
            AgentTool(name: "set_eds_display", title: "EDS map display settings",
                      summary: "Changes how the EDS room draws its maps, as a map's scale-bar popover and the colour mix's clicks do; "
                          + "only what is given changes, and a refused call changes nothing. maps names the maps the colour and contrast "
                          + "settings apply to (symbols, haadf for the scan image, or all). colour sets an element map's colour (a name "
                          + "from get_eds_display or #RRGGBB), colormap the scan image's; default_colouring returns to the room's own. "
                          + "low and high set the contrast window as fractions of the map's full scale, clip_percent sets it from the "
                          + "map's own percentiles (1: from the 1st to the 99th), gamma bends it (above 1 brightens the middle), "
                          + "reset_contrast is Reset Range. mix sets the maps in the colour mix (symbols and haadf, all, or none). "
                          + "scale_bar and regions are the Export section's switches for the maps figure. Display only: no number changes. "
                          + "Look with get_eds_figure.",
                      input: .window,
                      parameters: [
                          AgentParameter("maps", .text, summary: "The maps to change: \"Ni\", \"Fe, Ni\", \"haadf\" or \"all\"."),
                          AgentParameter("colour", .text, summary: "An element map's colour: a name (red, blue, sky_blue, ...) or #RRGGBB."),
                          AgentParameter("colormap", .choice(ColormapKind.allCases.map(\.rawValue)), summary: "The scan image's colormap."),
                          AgentParameter("default_colouring", .boolean, summary: "true: back to the map's own colour or colormap."),
                          AgentParameter("low", .number(0...1), summary: "Contrast window: the fraction of full scale drawn as the bottom colour."),
                          AgentParameter("high", .number(0...1), summary: "Contrast window: the fraction of full scale drawn as the top colour."),
                          AgentParameter("clip_percent", .number(0...49), summary: "Contrast window from the map's percentiles: clip_percent to 100 − clip_percent."),
                          AgentParameter("gamma", .number(0.2...3), summary: "Gamma, 0.2 to 3 as the popover's slider (1 leaves the map linear)."),
                          AgentParameter("reset_contrast", .boolean, summary: "true: Reset Range (the window and gamma the room starts with)."),
                          AgentParameter("mix", .text, summary: "The maps in the colour mix: symbols and haadf, \"all\" (the room's default: every element) or \"none\"."),
                          AgentParameter("scale_bar", .boolean, summary: "The maps figure draws the scale bar (the Export section's switch)."),
                          AgentParameter("regions", .boolean, summary: "The maps figure draws the regions (the Export section's switch)."),
                      ],
                      acts: true) { call in
                let r: (session: EDXSession, state: EDXRoomState)
                switch open(call) {
                case .failure(let refusal): return refusal.output
                case .success(let found): r = found
                }
                let s = r.session, state = r.state
                switch plan(call.arguments, session: s, state: state) {
                case .failure(let refusal): return refusal.output
                case .success(let change): change(state)
                }
                return .json(display(s, state))
            },
            AgentTool(name: "get_eds_figure", title: "EDS maps figure",
                      summary: "The EDS room's maps as Maps as PNG… draws them, with the person's colours, contrast, gamma and display "
                          + "filter: the colour mix first, then each map with its title and colour bar, the regions and the scale bar by "
                          + "the Export section's switches. maps draws only these element maps, side by side in that order; mix false "
                          + "leaves the colour mix out. Run quantify first for composition maps.",
                      input: .window,
                      parameters: [
                          AgentParameter("maps", .text, summary: "Only these element maps, in this order, e.g. \"Fe, Ni\"."),
                          AgentParameter("mix", .boolean, summary: "false: leave the colour mix out (default true)."),
                      ]) { call in
                let r: (session: EDXSession, state: EDXRoomState)
                switch open(call) {
                case .failure(let refusal): return refusal.output
                case .success(let found): r = found
                }
                let s = r.session, state = r.state
                var only: [String]?
                if let text = call.arguments["maps"] {
                    let asked = list(text), shown = s.shownTiles.map(\.symbol)
                    let unknown = asked.filter { !shown.contains($0) }
                    guard !asked.isEmpty, unknown.isEmpty else {
                        return .refusal(status: 404, message: "The room shows no map of \(unknown.isEmpty ? text : unknown.joined(separator: ", ")); "
                            + "it shows " + (shown.isEmpty ? "none." : shown.joined(separator: ", ") + "."))
                    }
                    only = asked
                }
                guard let png = state.mapsPNGNow(of: s, maps: only, mix: call.arguments["mix"] != "false") else {
                    return .refusal(status: 404, message: "The EDS room shows no map yet; wait until get_eds says not busy.")
                }
                return .png(png)
            },
        ]
    }

    struct Refusal: Error {
        let status: Int
        let message: String
        var output: AgentToolOutput { .refusal(status: status, message: message) }
    }

    /// "Fe, Ni" as ["Fe", "Ni"].
    static func list(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Every check of a `set_eds_display` call, before anything changes (as set_eds, EMSuiteUI#230); success is the change to make.
    static func plan(_ a: [String: String], session s: EDXSession, state: EDXRoomState) -> Result<(EDXRoomState) -> Void, Refusal> {
        let shown = state.mapDisplays(of: s)
        let perMap = ["colour", "colormap", "default_colouring", "low", "high", "clip_percent", "gamma", "reset_contrast"].filter { a[$0] != nil }
        var targets: [EDXMapDisplay] = []
        if let text = a["maps"] {
            let asked = list(text)
            if asked == ["all"] { targets = shown } else {
                let unknown = asked.filter { id in !shown.contains { $0.id == id } }
                guard !asked.isEmpty, unknown.isEmpty else {
                    return .failure(Refusal(status: 404, message: "The room shows no map of \(unknown.isEmpty ? text : unknown.joined(separator: ", ")); it shows "
                        + (shown.isEmpty ? "none." : shown.map(\.id).joined(separator: ", ") + ".")))
                }
                targets = asked.compactMap { id in shown.first { $0.id == id } }
            }
        }
        guard perMap.isEmpty || !targets.isEmpty else {
            return .failure(Refusal(status: 400, message: "Name the maps that \(perMap.joined(separator: ", ")) apply to (maps: symbols, haadf or all)."))
        }
        let colouring = ["colour", "colormap", "default_colouring"].filter { a[$0] != nil }
        guard colouring.count <= 1 else {
            return .failure(Refusal(status: 400, message: "Give one of colour, colormap and default_colouring, not \(colouring.joined(separator: " and "))."))
        }
        if a["reset_contrast"] == "true", let other = ["low", "high", "clip_percent", "gamma"].first(where: { a[$0] != nil }) {
            return .failure(Refusal(status: 400, message: "reset_contrast returns the window and gamma to the room's own; leave out \(other)."))
        }
        if a["clip_percent"] != nil, a["low"] != nil || a["high"] != nil {
            return .failure(Refusal(status: 400, message: "Give clip_percent or low and high, not both."))
        }

        var colorings: [String: MapColoring?] = [:]
        var adjustments: [(EDXMapDisplay, MapAdjustment?)] = []
        for map in targets {
            if let text = a["colour"] {
                guard !map.isReference else {
                    return .failure(Refusal(status: 409, message: "The scan image takes a colormap (\(ColormapKind.allCases.map(\.rawValue).joined(separator: ", "))), as its popover offers; colour is for element maps."))
                }
                guard let color = colour(named: text) else {
                    return .failure(Refusal(status: 400, message: "\(text) is no colour I know: give #RRGGBB or one of " + colours.map(\.name).joined(separator: ", ") + "."))
                }
                colorings[map.id] = .some(.color(color))
            } else if let kind = a["colormap"].flatMap(ColormapKind.init(rawValue:)) {
                guard map.isReference else {
                    return .failure(Refusal(status: 409, message: "\(map.id)'s map is black to one colour, as its popover offers; give colour. A colormap is for the scan image (haadf)."))
                }
                colorings[map.id] = .some(.colormap(kind))
            } else if a["default_colouring"] == "true" {
                colorings[map.id] = .some(nil)
            }

            if a["reset_contrast"] == "true" {
                adjustments.append((map, nil))
                continue
            }
            guard a["low"] != nil || a["high"] != nil || a["clip_percent"] != nil || a["gamma"] != nil else { continue }
            var adjustment = state.effectiveAdjustment(of: map)
            if let p = a["clip_percent"].flatMap(Double.init) {
                let sorted = map.values.filter(\.isFinite).sorted()
                guard map.top > 0, let lo = percentile(sorted, p), let hi = percentile(sorted, 100 - p), hi > lo else {
                    return .failure(Refusal(status: 409, message: "\(map.id)'s map is flat between those percentiles: there is no window to set."))
                }
                adjustment.low = min(max(lo / map.top, 0), 1)
                adjustment.high = min(max(hi / map.top, 0), 1)
            }
            if let low = a["low"].flatMap(Double.init) { adjustment.low = low }
            if let high = a["high"].flatMap(Double.init) { adjustment.high = high }
            if let gamma = a["gamma"].flatMap(Double.init) { adjustment.gamma = gamma }
            guard adjustment.high > adjustment.low else {
                return .failure(Refusal(status: 400, message: "\(map.id): low (\(adjustment.low)) must be below high (\(adjustment.high))."))
            }
            adjustments.append((map, adjustment))
        }

        var mix: ColorMix?
        if let text = a["mix"] {
            let selectable = EDXMapsComposition.selectable(scan: s.source?.scanImage, tiles: s.shownTiles)
            let asked = list(text)
            var chosen = ColorMix()
            if asked == ["none"] {
                chosen.isCustom = true
            } else if asked != ["all"] {
                let unknown = asked.filter { !selectable.contains($0) }
                guard !asked.isEmpty, unknown.isEmpty else {
                    return .failure(Refusal(status: 404, message: "The colour mix can take " + (selectable.isEmpty ? "no map yet." : selectable.joined(separator: ", ") + ".")
                        + (unknown.isEmpty ? "" : " Not \(unknown.joined(separator: ", ")).")))
                }
                chosen.members = selectable.filter(asked.contains)
                chosen.isCustom = true
            }
            mix = chosen
        }
        let scaleBar = a["scale_bar"].map { $0 == "true" }, regions = a["regions"].map { $0 == "true" }

        return .success({ state in
            for (id, coloring) in colorings { state.appearance.set(coloring, for: id) }
            for (map, adjustment) in adjustments {
                if let adjustment { state.setAdjustment(adjustment, of: map) } else { state.appearance.adjustments[map.id] = nil }
            }
            if let mix { state.appearance.mix = mix }
            if let scaleBar { state.exportScaleBar = scaleBar }
            if let regions { state.exportRegions = regions }
        })
    }

    /// The room's map display as an agent reads it.
    static func display(_ s: EDXSession, _ state: EDXRoomState) -> [String: Any] {
        let selection = EDXMapsComposition.selection(state.appearance.mix, scan: s.source?.scanImage, tiles: s.shownTiles)
        let maps = state.mapDisplays(of: s).map { map -> [String: Any] in
            let coloring = state.appearance.coloring(for: map.id, default: map.defaultColoring)
            let adjustment = state.effectiveAdjustment(of: map)
            var out: [String: Any] = [
                "id": map.id, "title": map.title, "unit": map.unit, "kind": map.isReference ? "scan_image" : "element",
                "custom_colouring": state.appearance.colorings[map.id] != nil,
                "low": adjustment.low, "high": adjustment.high, "gamma": adjustment.gamma,
                "custom_contrast": state.appearance.adjustments[map.id] != nil,
                "full_scale": AgentJSON.number(map.top),
                "in_mix": selection.contains(map.id),
            ]
            switch coloring {
            case .color(let c): out["colour"] = name(of: c)
            case .colormap(let kind): out["colormap"] = kind.rawValue
            }
            let sorted = map.values.filter(\.isFinite).sorted()
            if map.top > 0, !sorted.isEmpty {
                out["histogram"] = MapHistogram.bins(values: map.values, count: 32, range: 0...map.top)
                var marks: [String: Any] = [:]
                for q in percentiles {
                    guard let v = percentile(sorted, q) else { continue }
                    marks["p" + String(format: "%g", q)] = ["value": AgentJSON.number(v), "fraction": AgentJSON.number(min(max(v / map.top, 0), 1))]
                }
                out["percentiles"] = marks
            }
            return out
        }
        return [
            "maps": maps,
            "mix": selection,
            "display_filter": state.mapFilter.title,
            "figure_scale_bar": state.exportScaleBar,
            "figure_regions": state.exportRegions,
            "colours": colours.map { ["name": $0.name, "hex": hex($0.color), "colour_blind_safe": $0.colourBlindSafe] as [String: Any] },
            "colormaps": ColormapKind.allCases.map(\.rawValue),
        ]
    }

    static func hex(_ color: RegionColor) -> String {
        func byte(_ x: Double) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(color.red), byte(color.green), byte(color.blue))
    }
}
