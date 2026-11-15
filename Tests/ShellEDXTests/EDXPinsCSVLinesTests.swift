//
//  EDXPinsCSVLinesTests.swift
//  The pins CSV reads back whatever line ends it was saved with (#96): LF as written, CRLF from Windows (Excel, Notepad), CR alone, and a
//  quoted name that holds a line break. Only LF, CRLF and CR end a record; U+2028 and the other Unicode breaks stay in the name.
//  Red before: a CRLF file read as one line and gave no pins, and a name with a line break was dropped without a word.
//

import XCTest
import SpectroEDX
@testable import ShellEDXModel

nonisolated final class EDXPinsCSVLinesTests: XCTestCase {
    private static let header = "name,shape,geometry,pixels,counts,net_Al"
    private static let body = ["# EDS pins, file: scan.emd", header, "Left,rectangle,0 0 2 2,4,100,10", "\"Both, \"\"hot\"\"\",ellipse,0 0 2 1,2,50,5"]

    private func names(_ text: String) throws -> [String] {
        try XCTUnwrap(EDXPins.parse(text), "not read as a pins file").map(\.name)
    }

    func testEveryLineEndingReadsTheSamePins() throws {
        let expected = ["Left", "Both, \"hot\""]
        XCTAssertEqual(try names(Self.body.joined(separator: "\n") + "\n"), expected, "LF")
        XCTAssertEqual(try names(Self.body.joined(separator: "\r\n") + "\r\n"), expected, "CRLF")
        XCTAssertEqual(try names(Self.body.joined(separator: "\r") + "\r"), expected, "CR")
        XCTAssertEqual(try names(Self.body.joined(separator: "\r\n")), expected, "no line end after the last record")
    }

    func testAQuotedNameKeepsItsLineBreak() throws {
        for end in ["\n", "\r\n"] {
            let text = [Self.header, "\"Grain\(end)boundary\",rectangle,0 0 1 1,1,7,1", "Right,rectangle,1 0 2 1,1,3,0"].joined(separator: end) + end
            XCTAssertEqual(try names(text), ["Grain\nboundary", "Right"], "a quoted line break is the name's, not a record's end")
        }
    }

    func testOnlyLFCRLFAndCREndARecord() throws {
        let name = "a\u{2028}b\u{85}c"
        XCTAssertEqual(try names([Self.header, "\(name),rectangle,0 0 1 1,1,7,1"].joined(separator: "\n")), [name])
    }

    /// The writer quotes a name with a CR as it does one with an LF, so the pair reads back.
    func testANameWithACarriageReturnRoundTrips() throws {
        let pin = EDXPin(name: "x\ry", region: .rectangle(PixelRect(x0: 0, y0: 0, x1: 1, y1: 1)))
        let csv = EDXPins.csv(rows: [EDXPins.Row(pin: pin, pixels: 1, counts: 1, elements: [], net: [], weightPercent: nil, atomicPercent: nil)],
                              fileName: "f", title: "t")
        XCTAssertEqual(try names(csv), ["x\ny"], "quoted, so it stays one record; its break reads back as LF")
    }

    func testAFileThatIsNotPinsIsRefused() {
        XCTAssertNil(EDXPins.parse("a,b\r\n1,2\r\n"))
        XCTAssertNil(EDXPins.parse(""))
    }
}
