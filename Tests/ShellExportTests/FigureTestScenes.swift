import ShellExport

/// Pin G1's six scenes: an image, a pattern with a marker overlay, a pattern with a table, a spectrum as a path, a map with its
/// key, two phases with distinct marker shapes. Every number is a literal or exact arithmetic on literals, so the goldens are
/// the same on every Mac.
struct NamedScene: Sendable {
    let name: String
    let scene: FigureScene
    let metadata: FigureMetadata
}

enum FigureTestScenes {
    static let red = FigureColor(red: 1, green: 0, blue: 0)
    static let vermilion = FigureColor(red: 0.835, green: 0.369, blue: 0)
    static let blue = FigureColor(red: 0, green: 0.447, blue: 0.698)

    static var all: [NamedScene] { [image, overlay, table, spectrum, map, phases] }

    /// A gray picture whose neighbouring pixels differ by 30 across and 5 down: pixel (i, j) is 30 i + 5 j.
    static let gradient: FigureRaster = {
        var pixels: [UInt8] = []
        for j in 0..<6 {
            for i in 0..<8 { pixels.append(UInt8(30 * i + 5 * j)) }
        }
        return FigureRaster(width: 8, height: 6, format: .gray8, pixels: pixels)
    }()

    /// A 16 x 16 gray pattern: pixel (i, j) is ((i xor j) * 16) mod 256.
    static let pattern: FigureRaster = {
        var pixels: [UInt8] = []
        for j in 0..<16 {
            for i in 0..<16 { pixels.append(UInt8(((i ^ j) * 16) % 256)) }
        }
        return FigureRaster(width: 16, height: 16, format: .gray8, pixels: pixels)
    }()

    /// Where the image scene puts its picture: 20 points per pixel.
    static let imageFrame = FigureRect(x: 10, y: 10, width: 160, height: 120)

    static let image = NamedScene(
        name: "image",
        scene: FigureScene(heightMM: 60, layers: [
            .raster(gradient, frame: imageFrame),
            .path(.rectangle(FigureRect(x: 120, y: 120, width: 40, height: 3), fill: .white)),
            .text(FigureText("500 nm", at: FigurePoint(x: 140, y: 116), anchor: .middle, color: .white)),
            .text(FigureText("a", at: FigurePoint(x: 2, y: 8), size: 9, bold: true)),
        ]),
        metadata: FigureMetadata(title: "Image", creator: "EMSuiteUI tests"))

    /// The overlay's spot positions, the marker test's truth.
    static let spots = [FigurePoint(x: 85, y: 85), FigurePoint(x: 110.25, y: 85), FigurePoint(x: 59.75, y: 85),
                        FigurePoint(x: 85, y: 59.6)]

    static let overlay = NamedScene(
        name: "pattern-overlay",
        scene: FigureScene(heightMM: 60, layers: [
            .raster(pattern, frame: FigureRect(x: 10, y: 10, width: 150, height: 150)),
            .markers(FigureMarkers(shape: .circle, centers: spots, size: 6, stroke: red, lineWidth: 0.75)),
            .text(FigureText("000", at: FigurePoint(x: 85, y: 80), anchor: .middle, color: red)),
            .text(FigureText("200", at: FigurePoint(x: 110.25, y: 80), anchor: .middle, color: red)),
            .text(FigureText("-200", at: FigurePoint(x: 59.75, y: 80), anchor: .middle, color: red)),
            .text(FigureText("020", at: FigurePoint(x: 85, y: 54.6), anchor: .middle, color: red)),
        ]),
        metadata: FigureMetadata(title: "Pattern & overlay", creator: "EMSuiteUI tests",
                                 methodsRecord: #"{"room":"diffraction","version":1}"#))

    static let table = NamedScene(
        name: "pattern-table",
        scene: FigureScene(heightMM: 60, layers: [
            .raster(pattern, frame: FigureRect(x: 10, y: 10, width: 150, height: 150)),
            .table(FigureTable(origin: FigurePoint(x: 170, y: 10), columnWidths: [24, 30, 20], anchors: [.start, .end, .end],
                               header: ["hkl", "d (Å)", "I"],
                               rows: [["111", "2.338", "100"], ["200", "2.025", "47"], ["220", "1.432", "22"]])),
        ]),
        metadata: FigureMetadata(title: "Pattern with table", creator: "EMSuiteUI tests"))

    static let spectrumHeights: [Double] = [138, 137, 135, 130, 120, 100, 60, 30, 70, 110, 125, 131, 134, 120, 90, 118, 130,
                                            135, 137, 138, 138.5, 139]

    static let spectrum = NamedScene(
        name: "spectrum",
        scene: FigureScene(heightMM: 60, layers: [
            .path(FigurePath(points: [FigurePoint(x: 30, y: 10), FigurePoint(x: 30, y: 140), FigurePoint(x: 240, y: 140)])),
            .path(FigurePath(points: spectrumHeights.enumerated().map { FigurePoint(x: 30 + 10 * Double($0.offset), y: $0.element) },
                             stroke: blue, lineWidth: 0.75)),
            .text(FigureText("Counts", at: FigurePoint(x: 30, y: 7), anchor: .middle)),
            .text(FigureText("0", at: FigurePoint(x: 30, y: 150), anchor: .middle)),
            .text(FigureText("5", at: FigurePoint(x: 135, y: 150), anchor: .middle)),
            .text(FigureText("10", at: FigurePoint(x: 240, y: 150), anchor: .middle)),
            .text(FigureText("Energy (keV)", at: FigurePoint(x: 135, y: 160), anchor: .middle)),
            .text(FigureText("Fe Kα", at: FigurePoint(x: 100, y: 25), anchor: .middle)),
        ]),
        metadata: FigureMetadata(title: "Spectrum", creator: "EMSuiteUI tests"))

    /// A 4 x 3 map in three colours.
    static let mapRaster = FigureRaster(width: 4, height: 3, format: .rgb8, pixels: [
        255, 0, 0, 255, 0, 0, 0, 153, 0, 0, 153, 0,
        255, 0, 0, 0, 0, 255, 0, 0, 255, 0, 153, 0,
        0, 0, 255, 0, 0, 255, 0, 153, 0, 255, 0, 0,
    ])

    static let map = NamedScene(
        name: "map-key",
        scene: FigureScene(style: FigureStyle(width: .mm140), heightMM: 50, layers: [
            .raster(mapRaster, frame: FigureRect(x: 10, y: 10, width: 160, height: 120)),
            .legend(FigureLegend(origin: FigurePoint(x: 180, y: 10), entries: [
                FigureLegend.Entry("Fe", swatch: .box(FigureColor(red: 1, green: 0, blue: 0))),
                FigureLegend.Entry("Ni", swatch: .box(FigureColor(red: 0, green: 0.6, blue: 0))),
                FigureLegend.Entry("Cr", swatch: .box(FigureColor(red: 0, green: 0, blue: 1))),
            ])),
        ]),
        metadata: FigureMetadata(title: "Map", creator: "EMSuiteUI tests"))

    static let austenite = [FigurePoint(x: 40, y: 40), FigurePoint(x: 85, y: 40)]
    static let ferrite = [FigurePoint(x: 40, y: 100), FigurePoint(x: 130.5, y: 120)]

    static let phases = NamedScene(
        name: "two-phases",
        scene: FigureScene(style: FigureStyle(width: .mm190), heightMM: 60, layers: [
            .raster(pattern, frame: FigureRect(x: 10, y: 10, width: 150, height: 150)),
            .markers(FigureMarkers(shape: .circle, centers: austenite, size: 5, stroke: vermilion, lineWidth: 0.75)),
            .markers(FigureMarkers(shape: .triangle, centers: ferrite, size: 5, stroke: blue, lineWidth: 0.75)),
            .legend(FigureLegend(origin: FigurePoint(x: 170, y: 10), entries: [
                FigureLegend.Entry("Austenite (fcc)", swatch: .marker(.circle, stroke: vermilion, fill: nil)),
                FigureLegend.Entry("Ferrite (bcc)", swatch: .marker(.triangle, stroke: blue, fill: nil)),
            ])),
        ]),
        metadata: FigureMetadata(title: "Two phases", creator: "EMSuiteUI tests"))
}
