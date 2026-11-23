// swift-tools-version: 6.2
// SPDX-License-Identifier: GPL-3.0-only
// MacEMUI: the window shell, controls and Metal image view that mac4DSTEM and macTEM share.
// An app package, not a kit: it has UI, Metal and (named, minimal) AppKit. Kits stay pure Swift; imported here are ImagoCore for
// `ScaleBarMath` (ShellControls), for the shared EDS room SpectroKit, FormatoKit and ImagoFilters, and FormatoCore's PNG writer
// (ShellExport). No numerics live here.
// Settings: Swift 6 language mode and MainActor default isolation, as macTEM; mac4DSTEM (Swift 5 mode) consumes it unchanged.
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
        .library(name: "ShellCrystal", targets: ["ShellCrystal"]),
        .library(name: "ShellExport", targets: ["ShellExport"]),
    ],
    dependencies: [
        // ScaleBarMath (PaneFooter/ScaleBar). The apps pin exact tags.
        .package(url: "https://github.com/mac4DSTEM/ImagoKit", from: "0.7.0"),
        // The shared EDS room (ShellEDXModel, ShellSpectroscopy/EDX): SpectroKit holds its numerics, FormatoKit the MSA writer and the
        // provenance. The two move together (one HDF5 lock); the apps pin exact tags.
        .package(url: "https://github.com/mac4DSTEM/SpectroKit", from: "0.12.0"),
        .package(url: "https://github.com/mac4DSTEM/FormatoKit", from: "0.11.0"),
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
                dependencies: ["ShellMetal", "ShellControls", "ShellInspector", "ShellLayout", "ShellEDXModel",
                               .product(name: "SpectroCore", package: "SpectroKit"),
                               .product(name: "SpectroEDX", package: "SpectroKit")],
                swiftSettings: shellSettings),
        // The agent door both apps share (docs/agent-door.md): a local, read-only API an agent on this Mac reaches through the
        // MCP server over HTTP. Network.framework only; each app registers its own tools.
        .target(name: "ShellAgentDoor", swiftSettings: shellSettings),
        // The EDS room's agent tools, written once for both apps (each says how a window reaches its EDS session).
        .target(name: "ShellEDXAgent",
                dependencies: ["ShellAgentDoor", "ShellEDXModel", .product(name: "SpectroEDX", package: "SpectroKit")],
                swiftSettings: shellSettings),
        // The crystal view (docs/crystal-view.md): plain atoms, a cell and an orientation in, drawn with RealityKit. Imports no
        // kit: the app maps its structure and DiffractoKit's bonds into plain data.
        .target(name: "ShellCrystal", swiftSettings: shellSettings),
        // The figure scene and its PDF, SVG and PNG renderers: Core Graphics and Core Text, no SwiftUI, off the main actor.
        // FormatoCore writes the PNG with its text chunks.
        .target(name: "ShellExport",
                dependencies: [.product(name: "FormatoCore", package: "FormatoKit")],
                swiftSettings: modelSettings),
        .testTarget(name: "ShellMetalTests", dependencies: ["ShellMetal"], swiftSettings: shellSettings),
        .testTarget(name: "ShellControlsTests", dependencies: ["ShellControls"], swiftSettings: shellSettings),
        .testTarget(name: "ShellInspectorTests", dependencies: ["ShellInspector", "ShellLayout"], swiftSettings: shellSettings),
        .testTarget(name: "ShellLayoutTests", dependencies: ["ShellLayout"], swiftSettings: shellSettings),
        .testTarget(name: "ShellSpectroscopyTests", dependencies: ["ShellSpectroscopy", "ShellMetal", "ShellControls"], swiftSettings: shellSettings),
        .testTarget(name: "ShellCrystalTests", dependencies: ["ShellCrystal"], swiftSettings: shellSettings),
        .testTarget(name: "ShellExportTests",
                    dependencies: ["ShellExport", .product(name: "FormatoCore", package: "FormatoKit")],
                    exclude: ["Goldens"],
                    swiftSettings: modelSettings),
        .testTarget(name: "ShellAgentDoorTests", dependencies: ["ShellAgentDoor"], swiftSettings: shellSettings),
        .testTarget(name: "ShellEDXTests",
                    dependencies: ["ShellEDXModel", "ShellSpectroscopy", "ShellLayout", "ShellEDXAgent", "ShellAgentDoor",
                                   .product(name: "FormatoCore", package: "FormatoKit"),
                                   .product(name: "FormatoMSA", package: "FormatoKit"),
                                   .product(name: "SpectroCore", package: "SpectroKit"),
                                   .product(name: "SpectroEDX", package: "SpectroKit")],
                    exclude: ["Fixtures"],
                    swiftSettings: shellSettings),
    ]
)
