import XCTest
@testable import ShellMetal

/// EMSuite/MacEMUI#129: the 256-entry LUTs are matplotlib's own tables, not a handful of interpolated anchors. Expected bytes are
/// matplotlib 3.9.2's `_viridis_data`, `_inferno_data` and `_RdBu_data` entries times 255, rounded.
nonisolated final class ColormapTableTests: XCTestCase {
    private func rgb(_ kind: ColormapKind, _ i: Int) -> [UInt8] {
        let lut = Colormaps.lutRGBA(kind, count: 256)
        return Array(lut[(i * 4)..<(i * 4 + 3)])
    }

    func testViridisIsMatplotlibsTable() {
        XCTAssertEqual(rgb(.viridis, 0), [68, 1, 84])
        XCTAssertEqual(rgb(.viridis, 64), [59, 82, 139])
        XCTAssertEqual(rgb(.viridis, 255), [253, 231, 37])
    }

    func testInfernoIsMatplotlibsTable() {
        XCTAssertEqual(rgb(.inferno, 0), [0, 0, 4])
        XCTAssertEqual(rgb(.inferno, 64), [87, 16, 110])
        XCTAssertEqual(rgb(.inferno, 200), [251, 157, 7])
        XCTAssertEqual(rgb(.inferno, 255), [252, 255, 164])
    }

    /// RdBu runs blue (low) to red (high) here, matplotlib's RdBu_r: its darkest ends included, white in the middle.
    func testRdBuRunsFromMatplotlibsDarkBlueToItsDarkRed() {
        XCTAssertEqual(rgb(.rdbu, 0), [5, 48, 97])
        XCTAssertEqual(rgb(.rdbu, 255), [103, 0, 31])
        let middle = Colormaps.sampleRGB(Colormaps.lutRGBA(.rdbu), 0.5)
        for channel in [middle.0, middle.1, middle.2] { XCTAssertEqual(Double(channel), 247, accuracy: 2, "white in the middle") }
    }
}

/// EMSuite/MacEMUI#129: the 256-entry LUT is built once per colormap, not on every colorbar body or tile redraw.
nonisolated final class ColormapLUTCacheTests: XCTestCase {
    func testThe256EntryLUTIsBuiltOnce() {
        for kind in ColormapKind.allCases {
            let a = Colormaps.lutRGBA(kind), b = Colormaps.lutRGBA(kind, count: 256)
            let sameStorage = a.withUnsafeBufferPointer { pa in b.withUnsafeBufferPointer { pb in pa.baseAddress == pb.baseAddress } }
            XCTAssertTrue(sameStorage, "\(kind): one shared table")
            XCTAssertEqual(Colormaps.lutRGBA(kind, count: 44).count, 44 * 4, "other sizes are still built on request")
        }
    }
}
