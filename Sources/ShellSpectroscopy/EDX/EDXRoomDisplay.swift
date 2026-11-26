//
//  EDXRoomDisplay.swift
//  Role: the EDS room's map display as the agent door reads and sets it (Electron-Microscopy-Studio#672): each map the room shows, its
//        colouring, contrast window and gamma from the room's own `MapAppearance`, the values its tile draws (through the display filter,
//        as the scale bar's popover bins them), and the maps figure drawn now, as Maps as PNG… draws it, with the person's colours.
//
//        ONE SOURCE PER FACT: the values and the default window are `EDXTileDisplay.make`'s (the tile's and the popover's); the pictures
//        are `EDXMapTileHost.spec`'s rasters (`EDXRoomState.figureRasterJobs`, shared with the export) and `EDXMapsFigure.png`.
//

import Foundation
import ShellEDXModel
import ShellMetal
import SpectroCore

/// One map the room shows, as its tile draws it.
package struct EDXMapDisplay {
    /// The map's id in the appearance: the element's symbol, or "haadf" for the scan image.
    package var id: String
    package var title: String
    /// What the values are ("net counts", "wt%", "intensity").
    package var unit: String
    /// The scan image: coloured by a colormap; an element map is black to one colour.
    package var isReference: Bool
    /// The values the tile draws (composition maps through the display filter); NaN where the kit made none.
    package var values: [Double]
    /// The value that is full scale (fraction 1).
    package var top: Double
    /// The colouring until the person changes it.
    package var defaultColoring: MapColoring
    /// The window Reset Range returns to (the full range, or the percentile window of a filtered map).
    package var fallback: MapAdjustment
}

extension EDXRoomState {
    /// Every map the room shows, the scan image first, as its tile draws it.
    @MainActor package func mapDisplays(of session: EDXSession) -> [EDXMapDisplay] {
        var out: [EDXMapDisplay] = []
        if let scan = session.source?.scanImage {
            let (values, upper) = EDXTileDisplay.shifted(scan)
            out.append(EDXMapDisplay(id: "haadf", title: "HAADF", unit: "intensity", isReference: true, values: values, top: upper,
                                     defaultColoring: .colormap(.gray), fallback: MapAdjustment()))
        }
        let memo = session.filteredMaps
        for tile in session.shownTiles {
            let d = EDXTileDisplay.make(values: tile.values, width: tile.width, height: tile.height, top: tile.maxValue,
                                        filter: EDXMapTileHost.filter(of: tile, mapFilter), stored: nil,
                                        memo: (maps: memo, symbol: tile.symbol, version: tile.version))
            out.append(EDXMapDisplay(id: tile.symbol, title: tile.line, unit: tile.mode.unit, isReference: false, values: d.values,
                                     top: tile.maxValue, defaultColoring: EDXRegionBridge.defaultColoring(tile.symbol), fallback: d.fallback))
        }
        return out
    }

    /// The window a map is drawn with: the person's, or the one Reset Range returns to.
    package func effectiveAdjustment(of map: EDXMapDisplay) -> MapAdjustment { appearance.adjustments[map.id] ?? map.fallback }

    /// Sets a map's window and gamma as the scale bar's popover does: the window Reset Range returns to is not stored.
    package func setAdjustment(_ adjustment: MapAdjustment, of map: EDXMapDisplay) {
        appearance.adjustments[map.id] = adjustment == map.fallback ? nil : adjustment
    }

    /// The maps figure as Maps as PNG… draws it (the person's colours, contrast, gamma and display filter, the regions and scale bar by the
    /// export's switches), made now on the main actor: the agent door answers at once. `maps`: only these element maps, in this order
    /// (nil: every shown map); `mix`: whether the colour mix is drawn first. nil when the room shows no map.
    @MainActor package func mapsPNGNow(of session: EDXSession, maps: [String]? = nil, mix: Bool = true) -> Data? {
        let mixIDs = Set(EDXMapsComposition.selection(appearance.mix, scan: session.source?.scanImage, tiles: session.shownTiles))
        let mixTiles = mix ? session.shownTiles.filter { mixIDs.contains($0.symbol) } : []
        guard var content = session.figureContent(scaleBar: exportScaleBar, regions: exportRegions, mix: mixTiles, linesFocused: linesFocused) else {
            return nil
        }
        if let maps { content.keepTiles(maps) }
        guard !content.tiles.isEmpty || !content.mix.isEmpty else { return nil }
        var rasters: [String: [UInt8]] = [:]
        for job in Self.figureRasterJobs(of: session, appearance: appearance, filter: mapFilter) where rasters[job.key] == nil {
            rasters[job.key] = job.raster()
        }
        content.rasters = rasters
        return EDXMapsFigure.png(content)
    }
}
