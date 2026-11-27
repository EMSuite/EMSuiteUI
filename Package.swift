// swift-tools-version: 6.2
// SPDX-License-Identifier: GPL-3.0-only
// EMSuiteUI (package name MacEMUI until the module rename): the window shell, controls and Metal image view that
// 4DSTEM Studio and Electron Microscopy Studio share.
// An app package, not a kit: it has UI, Metal and (named, minimal) AppKit. Kits stay pure Swift; imported here are ImagoCore for
// `ScaleBarMath` (ShellControls), for the shared EDS room SpectroKit, FormatoKit and ImagoFilters, and FormatoCore's PNG writer
// (ShellExport). No numerics live here.
// Settings: Swift 6 language mode and MainActor default isolation, as Electron Microscopy Studio; 4DSTEM Studio (Swift 5 mode) consumes it unchanged.
import PackageDescription

let shellSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

// A model target that draws off the main actor (ShellExport): the shell's settings without the MainActor default.
let modelSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "MacEMUI",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ShellMetal", targets: ["ShellMetal"]),
        .library(name: "ShellControls", targets: ["ShellControls"]),
        .library(name: "ShellInspector", targets: ["ShellInspector"]),
        .library(name: "ShellLayout", targets: ["ShellLayout"]),
        .library(name: "ShellSpectroscopy", targets: ["ShellSpectroscopy"]),
        .library(name: "ShellEDXModel", targets: ["ShellEDXModel"]),
        .library(name: "ShellAgentDoor", targets: ["ShellAgentDoor"]),
        .library(name: "ShellEDXAgent", targets: ["ShellEDXAgent"]),
        // Test support: snapshot tests of SwiftUI views (suite#137), for this package's tests and the apps'.
        .library(name: "ShellSnapshotTesting", targets: ["ShellSnapshotTesting"]),
        .library(name: "ShellCrystal", targets: ["ShellCrystal"]),
        .library(name: "ShellExport", targets: ["ShellExport"]),
        .library(name: "ShellHelp", targets: ["ShellHelp"]),
        .library(name: "ShellPhaseLibrary", targets: ["ShellPhaseLibrary"]),
        .library(name: "ShellPhaseViews", targets: ["ShellPhaseViews"]),
        .library(name: "ShellQuickLook", targets: ["ShellQuickLook"]),
    ],
    dependencies: [
        // ScaleBarMath (PaneFooter/ScaleBar). The apps pin exact tags.
        .package(url: "https://github.com/EMSuite/ImagoKit", from: "0.7.0"),
        // The shared EDS room (ShellEDXModel, ShellSpectroscopy/EDX): SpectroKit holds its numerics, FormatoKit the MSA writer and the
        // provenance. The two move together (one HDF5 lock); the apps pin exact tags.
        .package(url: "https://github.com/EMSuite/SpectroKit", from: "0.12.0"),
        .package(url: "https://github.com/EMSuite/FormatoKit", from: "0.11.0"),
        // The phase library's structures (CrystalStructure.Snapshot). The apps pin exact tags.
        .package(url: "https://github.com/EMSuite/DiffractoKit", from: "0.21.0"),
    ],
    targets: [
        .target(name: "ShellMetal",
                resources: [.process("Resources")],   // Colormaps.metal; library loads with makeDefaultLibrary(bundle: .module)
                swiftSettings: shellSettings),
        .target(name: "ShellControls",
                dependencies: ["ShellMetal", .product(name: "ImagoCore", package: "ImagoKit")],
                swiftSettings: shellSettings),
        .target(name: "ShellInspector", dependencies: ["ShellControls"], swiftSettings: shellSettings),
        .target(name: "ShellLayout", dependencies: ["ShellControls"], swiftSettings: shellSettings),
        // The EDS room's model and session: no SwiftUI. Its numbers are SpectroKit's; this target chooses inputs and words results.
        .target(name: "ShellEDXModel",
                dependencies: [.product(name: "SpectroCore", package: "SpectroKit"),
                               .product(name: "SpectroEDX", package: "SpectroKit"),
                               .product(name: "FormatoCore", package: "FormatoKit"),
                               .product(name: "FormatoMSA", package: "FormatoKit"),
                               .product(name: "ImagoCore", package: "ImagoKit"),
                               .product(name: "ImagoFilters", package: "ImagoKit")],
                swiftSettings: shellSettings),
        .target(name: "ShellSpectroscopy",
                dependencies: ["ShellMetal", "ShellControls", "ShellInspector", "ShellLayout", "ShellEDXModel", "ShellExport",
                               .product(name: "SpectroCore", package: "SpectroKit"),
                               .product(name: "SpectroEDX", package: "SpectroKit")],
                swiftSettings: shellSettings),
        // The agent door both apps share (docs/agent-door.md): a local, read-only API an agent on this Mac reaches through the
        // MCP server over HTTP. Network.framework only; each app registers its own tools.
        .target(name: "ShellAgentDoor", swiftSettings: shellSettings),
        // The EDS room's agent tools, written once for both apps (each says how a window reaches its EDS session and, for the map
        // display tools, the room's view state).
        .target(name: "ShellEDXAgent",
                dependencies: ["ShellAgentDoor", "ShellEDXModel", "ShellSpectroscopy", "ShellMetal",
                               .product(name: "SpectroCore", package: "SpectroKit"), .product(name: "SpectroEDX", package: "SpectroKit")],
                swiftSettings: shellSettings),
        // Snapshot tests: a view drawn in light and dark and compared with the PNG committed beside its test. AppKit hosts the view
        // (NSHostingView) so AppKit-backed controls draw; no XCTest, so app targets may link it.
        .target(name: "ShellSnapshotTesting", swiftSettings: shellSettings),
        // The crystal view (docs/crystal-view.md): plain atoms, a cell and an orientation in, drawn with RealityKit. Imports no
        // kit: the app maps its structure and DiffractoKit's bonds into plain data.
        .target(name: "ShellCrystal", swiftSettings: shellSettings),
        // The figure scene and its PDF, SVG and PNG renderers, and the methods record and its paragraph: Core Graphics and Core
        // Text, no SwiftUI, off the main actor.
        // FormatoCore writes the PNG with its text chunks; a source's calibration is its FormatoMetadataEntry and provenance.
        .target(name: "ShellExport",
                dependencies: [.product(name: "FormatoCore", package: "FormatoKit")],
                swiftSettings: modelSettings),
        // The Help menu both apps share: the support and documentation links, a diagnostics summary and a feedback composer that
        // shows everything before the person's own mail app or browser sends it. The app itself sends nothing.
        .target(name: "ShellHelp", swiftSettings: shellSettings),
        // The phase library's model (docs: plan section 5.2): the record, the store, the key store and the Materials Project
        // client. No SwiftUI; the requests and the decoding are DiffractoKit's, this target sends and stores.
        .target(name: "ShellPhaseLibrary", dependencies: [.product(name: "DiffractoCore", package: "DiffractoKit")], swiftSettings: modelSettings),
        // The phase library's views: the Add Phase sheet (EMSuiteUI#189), its preview's unit-cell picture in the crystal view (#195),
        // My Phases and the lattice fields a room's inspector shows for the phase in use (EMSuiteUI#191).
        .target(name: "ShellPhaseViews",
                dependencies: ["ShellPhaseLibrary", "ShellInspector", "ShellCrystal", .product(name: "DiffractoCore", package: "DiffractoKit")],
                swiftSettings: shellSettings),
        // Quick Look for both apps' extensions (EMSuiteUI#225): the thumbnail's pixels and the preview card with its scale bar, from
        // FormatoKit's Peek. A sandboxed extension links it: FormatoPeek, ImagoCore (ScaleBarMath) and SwiftUI's ImageRenderer only.
        .target(name: "ShellQuickLook",
                dependencies: [.product(name: "FormatoPeek", package: "FormatoKit"), .product(name: "ImagoCore", package: "ImagoKit")],
                swiftSettings: modelSettings),
        .testTarget(name: "ShellMetalTests", dependencies: ["ShellMetal"], swiftSettings: shellSettings),
        .testTarget(name: "ShellControlsTests", dependencies: ["ShellControls"], swiftSettings: shellSettings),
        .testTarget(name: "ShellInspectorTests", dependencies: ["ShellInspector", "ShellLayout"], swiftSettings: shellSettings),
        .testTarget(name: "ShellLayoutTests", dependencies: ["ShellLayout"], swiftSettings: shellSettings),
        .testTarget(name: "ShellSpectroscopyTests", dependencies: ["ShellSpectroscopy", "ShellMetal", "ShellControls"], swiftSettings: shellSettings),
        .testTarget(name: "ShellSnapshotTests",
                    dependencies: ["ShellSnapshotTesting", "ShellControls", "ShellInspector", "ShellLayout", "ShellMetal"],
                    exclude: ["__Snapshots__"],
                    swiftSettings: shellSettings),
        .testTarget(name: "ShellCrystalTests", dependencies: ["ShellCrystal"], swiftSettings: shellSettings),
        .testTarget(name: "ShellExportTests",
                    dependencies: ["ShellExport", .product(name: "FormatoCore", package: "FormatoKit")],
                    exclude: ["Goldens"],
                    swiftSettings: modelSettings),
        .testTarget(name: "ShellPhaseLibraryTests", dependencies: ["ShellPhaseLibrary", .product(name: "DiffractoCore", package: "DiffractoKit")],
                    resources: [.copy("Fixtures")], swiftSettings: modelSettings),
        .testTarget(name: "ShellPhaseViewsTests",
                    dependencies: ["ShellPhaseViews", "ShellPhaseLibrary", "ShellInspector", "ShellSnapshotTesting", "ShellCrystal",
                                   .product(name: "DiffractoCore", package: "DiffractoKit")],
                    exclude: ["__Snapshots__"], resources: [.copy("Fixtures")], swiftSettings: shellSettings),
        .testTarget(name: "ShellAgentDoorTests", dependencies: ["ShellAgentDoor"], swiftSettings: shellSettings),
        .testTarget(name: "ShellHelpTests", dependencies: ["ShellHelp"], swiftSettings: shellSettings),
        .testTarget(name: "ShellQuickLookTests",
                    dependencies: ["ShellQuickLook", .product(name: "FormatoPeek", package: "FormatoKit"),
                                   .product(name: "ImagoCore", package: "ImagoKit")],
                    swiftSettings: modelSettings),
        .testTarget(name: "ShellEDXTests",
                    dependencies: ["ShellEDXModel", "ShellSpectroscopy", "ShellLayout", "ShellEDXAgent", "ShellAgentDoor", "ShellExport",
                                   .product(name: "FormatoCore", package: "FormatoKit"),
                                   .product(name: "FormatoMSA", package: "FormatoKit"),
                                   .product(name: "SpectroCore", package: "SpectroKit"),
                                   .product(name: "SpectroEDX", package: "SpectroKit")],
                    exclude: ["Fixtures"],
                    swiftSettings: shellSettings),
    ]
)
