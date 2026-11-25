//
//  EDXDisplayAgentToolsTests.swift
//  The EDS room's map display through the agent door (Electron-Microscopy-Studio#672), over a real door's MCP route on the planted spectrum
//  image of EDXSessionTests: an agent reads a map's colour, window, histogram and percentiles, makes Al blue and its contrast higher,
//  and sees the maps as Maps as PNG… draws them, all or one alone; a refused call changes nothing.
//

import XCTest
import SpectroEDX
@testable import ShellAgentDoor
@testable import ShellEDXModel
@testable import ShellSpectroscopy
@testable import ShellEDXAgent

private final class Window {
    let session: EDXSession
    let state = EDXRoomState()
    init(_ session: EDXSession) { self.session = session }
}

nonisolated final class EDXDisplayAgentToolsTests: XCTestCase {

    @MainActor private func door(_ window: Window) -> AgentDoor {
        let suite = "edx-display-agent-tools-\(UUID().uuidString)"
        let door = AgentDoor(appName: "TestApp", appVersion: "1.0", preferredPort: 0, defaults: UserDefaults(suiteName: suite)!)
        door.register(EDXAgentTools.tools { ($0 as? Window)?.session })
        door.register(EDXDisplayAgentTools.tools { owner in (owner as? Window).map { (session: $0.session, state: $0.state) } })
        door.enroll(window) { [:] }
        door.runsAllowed = true
        return door
    }

    @MainActor private func call(_ door: AgentDoor, _ name: String, _ arguments: [String: Any] = [:])
        throws -> (refused: Bool, json: [String: Any], text: String, png: Data?) {
        var request = AgentHTTPRequest(method: "POST", path: "/mcp", headers: ["host": "127.0.0.1:1"])
        request.body = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "tools/call",
                                                                   "params": ["name": name, "arguments": arguments]])
        let answer = try XCTUnwrap(try JSONSerialization.jsonObject(with: door.route(request).body) as? [String: Any])
        let result = try XCTUnwrap(answer["result"] as? [String: Any], "\(answer)")
        let content = (result["content"] as? [[String: Any]])?.first
        let text = (content?["text"] as? String) ?? ""
        let json = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
        let png = (content?["type"] as? String) == "image" ? (content?["data"] as? String).flatMap { Data(base64Encoded: $0) } : nil
        return (result["isError"] as? Bool ?? true, json, text, png)
    }

    private func map(_ json: [String: Any], _ id: String) -> [String: Any]? {
        (json["maps"] as? [[String: Any]])?.first { $0["id"] as? String == id }
    }

    /// Mutation: set_eds_display not reaching the room's appearance, get_eds_display reading another state, get_eds_figure drawing the default
    /// colours or every map when one is named, or a refused call leaving a colour applied - red.
    @MainActor func testAnAgentRecoloursAMapRaisesItsContrastAndSeesTheFigure() async throws {
        let session = EDXSession(host: .test)
        await session.bind(EDXSessionTests.source()).value
        await session.settled()
        let window = Window(session)
        let door = door(window)
        let picked = try call(door, "set_eds", ["remove": session.picks.map(\.symbol).joined(separator: ","), "add": "Al, Mg"])
        XCTAssertFalse(picked.refused, picked.text)
        await session.settled()
        XCTAssertEqual(Set(session.shownTiles.map(\.symbol)), ["Al", "Mg"], "precondition: two maps")

        // Read: the room's own colour and the full window; the histogram and percentiles of the values the tile draws.
        let read = try call(door, "get_eds_display")
        XCTAssertFalse(read.refused, read.text)
        let al = try XCTUnwrap(map(read.json, "Al"), read.text)
        XCTAssertEqual(al["custom_colouring"] as? Bool, false)
        XCTAssertNotNil(al["colour"] as? String)
        XCTAssertEqual(al["low"] as? Double, 0)
        XCTAssertEqual(al["high"] as? Double, 1)
        XCTAssertEqual((al["histogram"] as? [Int])?.reduce(0, +), 2, "both pixels binned")
        XCTAssertNotNil((al["percentiles"] as? [String: Any])?["p99"])
        XCTAssertTrue((read.json["colours"] as? [[String: Any]])?.contains { $0["name"] as? String == "sky_blue" && $0["colour_blind_safe"] as? Bool == true } ?? false)
        let before = try XCTUnwrap(call(door, "get_eds_figure").png, "the figure is a picture")

        // "Make Al blue, with more contrast."
        let set = try call(door, "set_eds_display", ["maps": "Al", "colour": "blue", "low": 0.1, "high": 0.5, "gamma": 2])
        XCTAssertFalse(set.refused, set.text)
        XCTAssertEqual(window.state.appearance.colorings["Al"], .color(RegionColor(red: 0, green: 0, blue: 1)), "the room's own appearance")
        XCTAssertEqual(window.state.appearance.adjustments["Al"], MapAdjustment(low: 0.1, high: 0.5, gamma: 2))
        XCTAssertNil(window.state.appearance.colorings["Mg"], "only the map named")
        XCTAssertEqual(map(set.json, "Al")?["colour"] as? String, "blue")
        XCTAssertEqual(map(set.json, "Al")?["gamma"] as? Double, 2)
        let after = try XCTUnwrap(call(door, "get_eds_figure").png)
        XCTAssertNotEqual(before, after, "the figure draws the agent's colour and window")
        let alone = try XCTUnwrap(call(door, "get_eds_figure", ["maps": "Al", "mix": false]).png)
        XCTAssertNotEqual(alone, after, "one map alone is another figure")
        XCTAssertTrue(try call(door, "get_eds_figure", ["maps": "Fe"]).refused, "no Fe map")

        // Refused calls change nothing.
        let refused: [(String, [String: Any])] = [
            ("an unknown map among known ones", ["maps": "Al, Fe", "colour": "red"]),
            ("a colour that is no colour", ["maps": "Al, Mg", "colour": "tartan"]),
            ("a colormap on an element map", ["maps": "Al", "colormap": "viridis"]),
            ("a window upside down after a colour", ["maps": "Mg, Al", "colour": "red", "low": 0.8, "high": 0.2]),
            ("a percentile clip beside a window", ["maps": "Al", "clip_percent": 1, "low": 0.2]),
            ("a reset beside a gamma", ["maps": "Al", "reset_contrast": true, "gamma": 1.5]),
            ("settings with no map named", ["colour": "red"]),
            ("a mix of a map not shown after a colour", ["maps": "Mg", "colour": "red", "mix": "Fe"]),
        ]
        let appearance = window.state.appearance
        for (why, arguments) in refused {
            let answer = try call(door, "set_eds_display", arguments)
            XCTAssertTrue(answer.refused, "\(why): \(answer.text)")
            XCTAssertEqual(window.state.appearance, appearance, why)
        }

        // Reset Range, the room's default colour, and the colour mix.
        XCTAssertFalse(try call(door, "set_eds_display", ["maps": "Al", "reset_contrast": true, "default_colouring": true]).refused)
        XCTAssertNil(window.state.appearance.adjustments["Al"])
        XCTAssertNil(window.state.appearance.colorings["Al"])
        let mixed = try call(door, "set_eds_display", ["mix": "Al", "scale_bar": false])
        XCTAssertFalse(mixed.refused, mixed.text)
        XCTAssertEqual(window.state.appearance.mix.members, ["Al"])
        XCTAssertTrue(window.state.appearance.mix.isCustom)
        XCTAssertEqual(mixed.json["mix"] as? [String], ["Al"])
        XCTAssertFalse(window.state.exportScaleBar)
        XCTAssertFalse(try call(door, "set_eds_display", ["mix": "all"]).refused)
        XCTAssertFalse(window.state.appearance.mix.isCustom)
        withExtendedLifetime(window) {}
    }

    /// Named colours read back by name, #RRGGBB by its hex; a percentile between ranks is linear. Mutation: name(of:) or percentile off - red.
    @MainActor func testColourNamesAndPercentiles() {
        XCTAssertEqual(EDXDisplayAgentTools.colour(named: "Sky Blue"), RegionPalette.colors[1])
        XCTAssertEqual(EDXDisplayAgentTools.colour(named: "#FF8000"), RegionColor(red: 1, green: 128.0 / 255, blue: 0))
        XCTAssertNil(EDXDisplayAgentTools.colour(named: "#FF80"))
        XCTAssertEqual(EDXDisplayAgentTools.name(of: RegionColor(red: 0, green: 0, blue: 1)), "blue")
        XCTAssertEqual(EDXDisplayAgentTools.name(of: RegionColor(red: 1, green: 128.0 / 255, blue: 0)), "#FF8000")
        XCTAssertEqual(EDXDisplayAgentTools.percentile([0, 10], 50), 5)
        XCTAssertEqual(EDXDisplayAgentTools.percentile([0, 10, 20], 100), 20)
        XCTAssertNil(EDXDisplayAgentTools.percentile([], 50))
    }
}
