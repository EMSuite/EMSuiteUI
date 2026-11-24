//
//  EDXRoomState.swift
//  Role: the EDX room's own view state (its spectrum window and the export in flight). The room's facts are
//        `EDXSession`'s (TEMSession); this holds only what the views share between the centre and the inspector.
//        Window-wide and not saved; composed by `AppState` as `ResultsRoomState` is.
//

import Foundation
import Observation
import SpectroCore
import UniformTypeIdentifiers
import ShellEDXModel
import ShellExport

/// What the Export section writes: text (the results, the method, the spectrum as CSV or `.msa`, the pins) or the maps as a PNG.
public nonisolated enum EDXExportKind: String, Identifiable, CaseIterable {
    case results, method, spectrum, spectrumMSA, pins, mapsPNG
    /// The spectrum and the maps as vector figures (Electron-Microscopy-Studio#902): live text, the spectrum one path.
    case spectrumPDF, spectrumSVG, mapsPDF, mapsSVG
    /// Every phase pool fitted with the room's method (mac4DSTEM; made by the window, `EDXRoomActions.exportCompositionByClass`).
    case compositionByClass

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .results: "Results as CSV…"
        case .method: "Method as JSON…"
        case .spectrum: "Spectrum as CSV…"
        case .spectrumMSA: "Spectrum as MSA…"
        case .pins: "Pinned regions as CSV…"
        case .mapsPNG: "Maps as PNG…"
        case .spectrumPDF: "Spectrum as PDF…"
        case .spectrumSVG: "Spectrum as SVG…"
        case .mapsPDF: "Maps as PDF…"
        case .mapsSVG: "Maps as SVG…"
        case .compositionByClass: "Composition by class as CSV…"
        }
    }

    /// The EMSA/MSA spectrum file, by its extension (no system type declares it); `EDXExportFile` lists it among the types it writes.
    public static let msa = UTType(filenameExtension: "msa") ?? .plainText

    public var contentType: UTType {
        switch self {
        case .method: .json
        case .mapsPNG: .png
        case .spectrumPDF, .mapsPDF: .pdf
        case .spectrumSVG, .mapsSVG: .svg
        case .spectrumMSA: Self.msa
        default: .commaSeparatedText
        }
    }

    /// The file name's tail: "Sample Whole_map quantification".
    public var suffix: String {
        switch self {
        case .results: " quantification"
        case .method: " method"
        case .spectrum, .spectrumMSA, .spectrumPDF, .spectrumSVG: " spectrum"
        case .pins: " pins"
        case .mapsPNG, .mapsPDF, .mapsSVG: " maps"
        case .compositionByClass: " composition by class"
        }
    }

    /// The vector format of a figure's kind; nil for the files that are no figure and for the PNG.
    public var figureFormat: EDXFigureFormat? {
        switch self {
        case .spectrumPDF, .mapsPDF: .pdf
        case .spectrumSVG, .mapsSVG: .svg
        case .results, .method, .spectrum, .spectrumMSA, .pins, .mapsPNG, .compositionByClass: nil
        }
    }
}

package struct EDXHoverPixel: Equatable {
    public var x: Int
    public var y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
}

@Observable
public final class EDXRoomState {
    public init() {}

    /// The drawing tool of the header's picker.
    public var tool: RegionTool = .pointer
    /// The tile shown alone after a double click (nil: the grid).
    public var soloTile: String?
    /// The zoom and position every map shares (pinch, scroll, drag; a double click resets).
    public var mapView = MapViewTransform()
    /// How the maps are coloured and the colour mix (the inspector's Maps section); window-wide, reset with a new file.
    public var appearance = MapAppearance()
    /// The display filter of the wt%, at% and Thickness tiles (never of the net maps or the HAADF, never of a number).
    package var mapFilter: EDXMapFilter = .mean3x3
    /// The pixel under the pointer on any map (its spectrum is the temporary layer); nil off the maps.
    package var hoverPixel: EDXHoverPixel?
    /// The status line's cursor readout: the pixel and its value over a map, the energy and counts over the spectrum; nil when the pointer is elsewhere.
    public var readout: String?
    /// Whether the Regions list's selection (and the heavier outline) belongs to a line, the last thing the person drew or picked, or to a region.
    public var linesFocused = false
    /// Bumped by every "Open Spectrum Image…" gesture; the room presents the open panel when it changes.
    public private(set) var importRequest = 0
    /// The export whose save panel is up, and its bytes (made before the panel opens: the pins and the figure are made off the click).
    public var exporting: EDXExportKind?
    public private(set) var exportData = Data()
    /// The energy window the spectrum shows, keV; nil = the automatic one (the picked elements' lines, or where the counts are).
    public var window: ClosedRange<Double>?
    /// How far the counts axis is zoomed in (1: the automatic top).
    public var yZoom = 1.0
    /// What the maps export draws besides the pictures.
    public var exportScaleBar = true
    public var exportRegions = true
    /// What the app does to an export's bytes before they are written or handed to the save panel (Electron Microscopy Studio puts its
    /// methods record inside, Electron-Microscopy-Studio#817); nil writes the bytes as made. It gets the bytes, the kind and the session.
    @ObservationIgnored public var finishExport: (@MainActor (Data, EDXExportKind, EDXSession) async -> Data)?
    /// What a vector figure carries in its metadata (Electron-Microscopy-Studio#902): the app's software line and methods record, made
    /// before the figure is drawn; nil names the file and the app's bundle name and version, with no record.
    @ObservationIgnored public var figureMetadata: (@MainActor (EDXExportKind, EDXSession) async -> FigureMetadata)?

    public func requestImport() { importRequest &+= 1 }

    /// Esc: back to the arrow tool; a shape half drawn (an open polygon) goes with its tool. False when the arrow was already chosen,
    /// so the key is left to whatever else wants it.
    @discardableResult package func escape() -> Bool {
        guard tool != .pointer else { return false }
        tool = .pointer
        return true
    }

    /// Makes the bytes of `kind` from the session and opens the save panel (or, with `directory`, the UI journeys' export folder, writes the file there
    /// as the other rooms' exports do); says why when there is nothing to write.
    @MainActor public func export(_ kind: EDXExportKind, from session: EDXSession, directory: URL? = nil, report: (String) -> Void) async {
        let data: Data?
        switch kind {
        case .results: data = session.resultsCSV.map { Data($0.utf8) }
        case .method: data = session.methodJSON.map { Data($0.utf8) }
        case .spectrum: data = session.spectrumCSV.map { Data($0.utf8) }
        case .spectrumMSA:
            do { data = try session.spectrumMSA() } catch { report("MSA export failed: \(error.localizedDescription)"); return }
        case .pins: data = await session.pinsCSV().map { Data($0.utf8) }
        case .mapsPNG:
            data = await mapsContent(of: session).flatMap(EDXMapsFigure.png)
        case .spectrumPDF, .spectrumSVG, .mapsPDF, .mapsSVG:
            let scene: FigureScene?
            if kind == .spectrumPDF || kind == .spectrumSVG {
                scene = session.spectrumFigure(window: window).map { FigurePlot.spectrum($0, style: FigureStyle(width: .mm90)) }
            } else {
                scene = await mapsContent(of: session)?.vectorScene()
            }
            guard let scene, let format = kind.figureFormat else { data = nil; break }
            var metadata = FigureMetadata(title: session.fileName, creator: Self.creator())
            if let figureMetadata { metadata = await figureMetadata(kind, session) }
            do { data = try await EDXFigureFormat.data(scene, format: format, metadata: metadata) } catch {
                report("Export failed: \(error.localizedDescription)"); return
            }
        case .compositionByClass: data = nil   // made by the window, which holds the pools (`save`)
        }
        var finished = data
        // A figure carries its record in its metadata already; the hook embeds one in the other files.
        if let made = data, kind.figureFormat == nil, let finishExport { finished = await finishExport(made, kind, session) }
        save(finished, kind: kind, stem: session.exportStem, directory: directory, report: report)
    }

    /// What the maps figure draws: the shown tiles, the colour mix, the regions and the scale bar by the export's toggles, each map's
    /// pixels as its tile draws them.
    @MainActor func mapsContent(of session: EDXSession) async -> EDXFigureContent? {
        let mixIDs = Set(EDXMapsComposition.selection(appearance.mix, scan: session.source?.scanImage, tiles: session.shownTiles))
        let mix = session.shownTiles.filter { mixIDs.contains($0.symbol) }
        guard var content = session.figureContent(scaleBar: exportScaleBar, regions: exportRegions, mix: mix, linesFocused: linesFocused) else {
            return nil
        }
        content.rasters = await Self.figureRasters(of: session, appearance: appearance, filter: mapFilter)
        return content
    }

    /// The software line of a figure the app names none for: "Electron Microscopy Studio 2.5.0".
    nonisolated static func creator(info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        let name = info?["CFBundleName"] as? String ?? "EMSuite"
        guard let version = info?["CFBundleShortVersionString"] as? String else { return name }
        return name + " " + version
    }

    /// The maps as the room's tiles draw them (`EDXMapTileHost.spec`: the person's colours, contrast, gamma and display filter), made off the main
    /// actor: each element map by its symbol, the colour mix under `EDXFigureContent.mixKey` (EMSuiteUI#125).
    @MainActor static func figureRasters(of session: EDXSession, appearance: MapAppearance, filter: EDXMapFilter) async -> [String: [UInt8]] {
        let items = EDXMapsComposition.items(scan: session.source?.scanImage, tiles: session.shownTiles, appearance: appearance)
        let width = session.source?.nx ?? 0, memo = session.filteredMaps
        var jobs: [(key: String, raster: @Sendable () -> [UInt8])] = []
        if let anchor = items.anchor, case .mix(let members) = anchor.kind, !members.isEmpty {
            jobs.append((EDXFigureContent.mixKey, EDXMapTileHost.spec(for: anchor, appearance: appearance, filter: filter, width: width, memo: memo).raster))
        }
        for item in items.rest {
            guard case .map(let tile) = item.kind else { continue }
            jobs.append((tile.symbol, EDXMapTileHost.spec(for: item, appearance: appearance, filter: filter, width: width, memo: memo).raster))
        }
        let keys = jobs.map(\.key), rasters = jobs.map(\.raster)
        let made = await Task.detached(priority: .userInitiated) { rasters.map { $0() } }.value
        return Dictionary(zip(keys, made), uniquingKeysWith: { first, _ in first })
    }

    /// The save panel closed: its bytes go (EMSuiteUI#125: the maps PNG stayed in the state after saving).
    package func exportFinished() {
        exporting = nil
        exportData = Data()
    }

    /// Writes `data` as `kind` through the save panel, or into `directory` (a UI journey's export folder); says why when there is nothing.
    @MainActor public func save(_ data: Data?, kind: EDXExportKind, stem: String, directory: URL? = nil, report: (String) -> Void) {
        guard let data else { report("Nothing to export yet for \(kind.title.dropLast())."); return }
        if let directory {
            let url = directory.appendingPathComponent(stem + kind.suffix).appendingPathExtension(kind.contentType.preferredFilenameExtension ?? "txt")
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: url)
                report("Exported \(url.lastPathComponent)")
            } catch { report("Export failed: \(error.localizedDescription)") }
            return
        }
        exportData = data
        exporting = kind
    }
}
