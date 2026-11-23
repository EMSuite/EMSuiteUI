// swift-tools-version: 6.2
// MU0 spike (EMSuiteUI #192): does RealityKit draw the crystal view with parallel projection at speed?
// Throwaway. Never merged. Run by run-mac-spike.sh on the reference Mac.
import PackageDescription

let package = Package(
    name: "CrystalSpike",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "CrystalSpike", swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
