//
//  EDXAgentToolsTests.swift
//  The EDS room's agent tools (ShellEDXAgent) over a real door's MCP route, on the planted spectrum image of EDXSessionTests:
//  an agent picks the elements and the region, quantifies, and reads the table as numbers, as the person's controls would.
//

import XCTest
import SpectroEDX
@testable import ShellAgentDoor
@testable import ShellEDXModel
import ShellEDXAgent

private final class Window {
    let session: EDXSession
    init(_ session: EDXSession) { self.session = session }
}

nonisolated final class EDXAgentToolsTests: XCTestCase {

    @MainActor private func door(_ window: Window) -> AgentDoor {
        let suite = "edx-agent-tools-\(UUID().uuidString)"
        let door = AgentDoor(appName: "TestApp", appVersion: "1.0", preferredPort: 0, defaults: UserDefaults(suiteName: suite)!)
        door.register(EDXAgentTools.tools { ($0 as? Window)?.session })
        door.enroll(window) { [:] }
        door.runsAllowed = true
        return door
    }

    @MainActor private func call(_ door: AgentDoor, _ name: String, _ arguments: [String: Any] = [:]) throws -> (refused: Bool, json: [String: Any], text: String) {
        var request = AgentHTTPRequest(method: "POST", path: "/mcp", headers: ["host": "127.0.0.1:1"])
        request.body = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "tools/call",
                                                                   "params": ["name": name, "arguments": arguments]])
        let answer = try XCTUnwrap(try JSONSerialization.jsonObject(with: door.route(request).body) as? [String: Any])
        let result = try XCTUnwrap(answer["result"] as? [String: Any], "\(answer)")
        let text = ((result["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        let json = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
        return (result["isError"] as? Bool ?? true, json, text)
    }

    /// Mutation: set_eds picks the wrong element or ignores the region, run_eds does not quantify, or get_eds leaves out the table - red.
    @MainActor func testAnAgentQuantifiesTheRoomAndReadsTheTable() async throws {
        let empty = Window(EDXSession(host: .test))
        let closed = door(empty)
        XCTAssertTrue(try call(closed, "get_eds").refused, "no spectrum image yet")

        let session = EDXSession(host: .test)
        await session.bind(EDXSessionTests.source()).value
        await session.settled()
        let window = Window(session)
        let door = door(window)

        XCTAssertTrue(try call(door, "set_eds", ["add": "Xx"]).refused, "not an element")
        XCTAssertTrue(try call(door, "set_eds", ["fit_only": "Au"]).refused, "not picked")
        let picked = try call(door, "set_eds", ["remove": session.picks.map(\.symbol).joined(separator: ","), "add": "Al, Mg, Si",
                                                "region": "rectangle", "x0": 0, "y0": 0, "x1": 1, "y1": 1])
        XCTAssertFalse(picked.refused, picked.text)
        await session.settled()
        XCTAssertEqual(Set(session.picks.map(\.symbol)), ["Al", "Mg", "Si"])
        XCTAssertEqual(session.regionPixels, 1, "the left pixel only")

        let started = try call(door, "run_eds", ["action": "quantify"])
        XCTAssertFalse(started.refused, started.text)
        await session.settled()
        XCTAssertNotNil(session.fit, session.fitFailure ?? "")

        let read = try call(door, "get_eds")
        XCTAssertFalse(read.refused, read.text)
        XCTAssertEqual(read.json["busy"] as? Bool, false)
        let csv = try XCTUnwrap(read.json["results_csv"] as? String, read.text)
        XCTAssertEqual(csv, session.resultsCSV, "the table is the room's own CSV")
        XCTAssertTrue(csv.contains("Al") && csv.contains("Mg") && csv.contains("Si"))
        XCTAssertEqual((read.json["picks"] as? [[String: Any]])?.count, 3)

        XCTAssertTrue(try call(door, "set_eds", ["region": "pin", "pin": "nothing"]).refused)
        XCTAssertFalse(try call(door, "set_eds", ["region": "whole"]).refused)
        await session.settled()
        XCTAssertEqual(session.region, .wholeMap)
        withExtendedLifetime(window) {}
        withExtendedLifetime(empty) {}
    }

    /// The Workspace menu's Polygon Region Tool, Line Tool and Pin Region through set_eds (EMSuite/Electron-Microscopy-Studio#885).
    /// Mutation: set_eds ignores vertices, keep or line, or get_eds leaves out the lines - red.
    @MainActor func testAnAgentDrawsAPolygonKeepsARegionAndDrawsALine() async throws {
        let session = EDXSession(host: .test)
        await session.bind(EDXSessionTests.source()).value
        await session.settled()
        let window = Window(session)
        let door = door(window)

        XCTAssertTrue(try call(door, "set_eds", ["region": "polygon", "vertices": "0,0; 1,0"]).refused, "two vertices")
        XCTAssertTrue(try call(door, "set_eds", ["region": "polygon", "vertices": "0,0; 1,x; 1,1"]).refused, "not a number")
        XCTAssertTrue(try call(door, "set_eds", ["region": "polygon", "vertices": "5,5; 6,5; 6,6"]).refused, "outside the scan")
        let many = try call(door, "set_eds", ["region": "polygon", "vertices": (0...1000).map { "\($0 % 2),\($0 % 3)" }.joined(separator: ";")])
        XCTAssertTrue(many.refused && many.text.contains("at most 1000 vertices"), "1001 vertices: \(many.text)")
        let drawn = try call(door, "set_eds", ["region": "polygon", "vertices": "0,0; 1.2,0; 1.2,1; 0,1"])
        XCTAssertFalse(drawn.refused, drawn.text)
        await session.settled()
        XCTAssertEqual(session.region, .polygon([PixelPoint(x: 0, y: 0), PixelPoint(x: 1.2, y: 0), PixelPoint(x: 1.2, y: 1), PixelPoint(x: 0, y: 1)]))
        XCTAssertEqual(session.regionPixels, 1, "the left pixel only")
        XCTAssertEqual(drawn.json["kept_regions"] as? [String], ["Region 1"], "a drawn polygon is kept, as a drawing on the map is")

        // Pin Region: the whole map is not kept by selecting it; keep keeps it under its name.
        XCTAssertFalse(try call(door, "set_eds", ["region": "whole"]).refused)
        let kept = try call(door, "set_eds", ["keep": true, "name": "All of it"])
        XCTAssertFalse(kept.refused, kept.text)
        XCTAssertEqual(kept.json["kept_regions"] as? [String], ["Region 1", "All of it"])
        XCTAssertEqual(session.selectedPin?.name, "All of it")

        XCTAssertTrue(try call(door, "set_eds", ["line": "0,0"]).refused, "one end")
        XCTAssertTrue(try call(door, "set_eds", ["line": "0,0, 0.2,0"]).refused, "shorter than a pixel")
        let line = try call(door, "set_eds", ["line": "0,0.5, 2,0.5"])
        XCTAssertFalse(line.refused, line.text)
        XCTAssertEqual(line.json["lines"] as? [String], ["Line 1"])
        XCTAssertEqual(session.lines.first?.from, PixelPoint(x: 0, y: 0.5))
        XCTAssertEqual(session.lines.first?.to, PixelPoint(x: 2, y: 0.5))
        XCTAssertEqual(try call(door, "get_eds").json["lines"] as? [String], ["Line 1"])

        // A region drawn and kept under a name in one call carries that name, not "Region n" (#230).
        let named = try call(door, "set_eds", ["region": "rectangle", "x0": 0, "y0": 0, "x1": 1, "y1": 1, "keep": true, "name": "Grain A"])
        XCTAssertFalse(named.refused, named.text)
        XCTAssertEqual(named.json["kept_regions"] as? [String], ["Region 1", "All of it", "Grain A"])
        XCTAssertEqual(session.selectedPin?.name, "Grain A")
        XCTAssertFalse(try call(door, "set_eds", ["region": "whole"]).refused)
        XCTAssertFalse(try call(door, "set_eds", ["region": "pin", "pin": "Grain A"]).refused)
        XCTAssertEqual(session.selectedPin?.name, "Grain A")
        withExtendedLifetime(window) {}
    }

    /// A refused set_eds changes nothing: every check (symbols, availability, roles against the picks as they will be, the region, the line)
    /// runs before the first change (EMSuiteUI#230 part 2).
    /// Mutation: set_eds removes before it checks the additions or the roles, picks before it checks the region, or draws the region before it
    /// checks the line - red.
    @MainActor func testARefusedCallLeavesTheRoomAsItWas() async throws {
        let session = EDXSession(host: .test)
        await session.bind(EDXSessionTests.source()).value
        await session.settled()
        let window = Window(session)
        let door = door(window)
        let start = try call(door, "set_eds", ["remove": session.picks.map(\.symbol).joined(separator: ","), "add": "Al, Mg"])
        XCTAssertFalse(start.refused, start.text)
        await session.settled()

        func state() -> [String] {
            session.picks.map { "\($0.symbol):\($0.role == .quantify ? "q" : "f")" }
                + ["region \(session.region)", "pins \(session.pins.map(\.name))", "lines \(session.lines.map(\.name))"]
        }
        let before = state()
        XCTAssertEqual(Set(before.prefix(2)), ["Al:q", "Mg:q"], "the picks keep their own order (Mg before Al); only the set matters here")
        let refused: [(String, [String: Any])] = [
            ("an addition that cannot be picked", ["remove": "Al", "add": "Be"]),
            ("a role for an element the call takes out", ["remove": "Al", "quantify": "Al", "fit_only": "Mg"]),
            ("a kept region that does not exist", ["fit_only": "Mg", "region": "pin", "pin": "nothing"]),
            ("a rectangle outside the scan", ["add": "Si", "region": "rectangle", "x0": 5, "y0": 5, "x1": 6, "y1": 6]),
            ("a polygon outside the scan", ["remove": "Mg", "region": "polygon", "vertices": "5,5; 6,5; 6,6"]),
            ("a line shorter than a pixel", ["region": "rectangle", "x0": 0, "y0": 0, "x1": 1, "y1": 1, "keep": true, "name": "Grain A",
                                            "line": "0,0, 0.2,0"]),
            ("a line on bad numbers", ["add": "Si", "line": "0,0, x,1"]),
        ]
        for (why, arguments) in refused {
            let answer = try call(door, "set_eds", arguments)
            XCTAssertTrue(answer.refused, "\(why): \(answer.text)")
            await session.settled()
            XCTAssertEqual(state(), before, why)
        }

        // Roles are checked against the picks as the call leaves them: an element added in the same call takes its role.
        let both = try call(door, "set_eds", ["remove": "Mg", "add": "Si", "fit_only": "Si"])
        XCTAssertFalse(both.refused, both.text)
        await session.settled()
        XCTAssertEqual(state().prefix(2), ["Al:q", "Si:f"])
        withExtendedLifetime(window) {}
    }
}
