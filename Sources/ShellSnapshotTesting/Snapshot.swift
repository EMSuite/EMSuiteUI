// Snapshot tests for SwiftUI views, shared by MacEMUI and both apps (suite#137): a view is drawn into a window at a fixed
// size, in light and in dark, at 2x, and compared with the PNG committed beside its test. A missing or changed picture
// fails the test and is written to the artifacts folder, which CI attaches to the pull request; the PR picture is then the
// snapshot, not a drive of the Mac.
//
// Pictures differ between macOS versions and between Macs (fonts, AppKit's controls), so the references are the ones CI
// draws on GitHub's macos-26 runner, and a test compares only where SNAPSHOTS=1 is set (that CI leg). Anywhere else the
// check reports `.skipped` and the test skips. No XCTest here, so an app target may link it; the test asserts the result.
//
// AppKit: NSHostingView and NSWindow host the view so that AppKit-backed controls (pickers, fields, toggles) draw as they do
// on screen; SwiftUI's ImageRenderer leaves those out.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

/// The appearance a snapshot is drawn in; its raw value ends the picture's file name.
public nonisolated enum SnapshotAppearance: String, CaseIterable, Sendable {
    case light
    case dark

    var name: NSAppearance.Name { self == .light ? .aqua : .darkAqua }
}

/// What one comparison found.
public nonisolated enum SnapshotResult: Equatable, Sendable {
    /// The picture matches its reference.
    case matched
    /// Not compared: snapshots are compared only where SNAPSHOTS=1 is set.
    case skipped(String)
    /// No reference is committed; the new picture was written to `written`.
    case recorded(written: String)
    /// The picture differs from its reference; the new one was written to `written`.
    case differs(String, written: String)
    /// The view could not be drawn.
    case failed(String)

    /// A sentence for the test's failure message, or nil when the result passes.
    public var failure: String? {
        switch self {
        case .matched, .skipped: nil
        case .recorded(let written):
            "No reference picture is committed. The new one is at \(written); review it and commit it beside the test."
        case .differs(let detail, let written):
            "The picture differs from its reference (\(detail)). The new one is at \(written)."
        case .failed(let detail): "The view could not be drawn: \(detail)"
        }
    }
}

public enum Snapshot {
    /// True where pictures are compared: SNAPSHOTS=1 (CI's macos-26 leg).
    public static var isEnabled: Bool { ProcessInfo.processInfo.environment["SNAPSHOTS"] == "1" }

    /// Where new and changed pictures go: SNAPSHOT_ARTIFACTS, else a folder in the temporary directory.
    public static var artifactsFolder: URL {
        if let path = ProcessInfo.processInfo.environment["SNAPSHOT_ARTIFACTS"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("snapshots", isDirectory: true)
    }

    /// Draws `view` at `size` points in `appearance` and compares it with
    /// `<folder of testFile>/__Snapshots__/<testFile name>/<name>.<appearance>.png`.
    ///
    /// SNAPSHOT_RECORD=1 also writes the new picture over the reference (a deliberate change).
    public static func verify<V: View>(_ view: V, named name: String, size: CGSize, appearance: SnapshotAppearance,
                                       testFile: StaticString = #filePath) -> SnapshotResult {
        guard isEnabled else { return .skipped("snapshots are compared only where SNAPSHOTS=1 is set") }
        let file = URL(fileURLWithPath: "\(testFile)")
        let group = file.deletingPathExtension().lastPathComponent
        let fileName = "\(name).\(appearance.rawValue).png"
        let reference = file.deletingLastPathComponent().appendingPathComponent("__Snapshots__", isDirectory: true)
            .appendingPathComponent(group, isDirectory: true).appendingPathComponent(fileName)
        let written = artifactsFolder.appendingPathComponent(group, isDirectory: true).appendingPathComponent(fileName)

        guard let png = render(view, size: size, appearance: appearance) else {
            return .failed("no bitmap for \(fileName)")
        }
        let record = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"
        guard let old = try? Data(contentsOf: reference) else {
            if let problem = write(png, to: written, alsoTo: record ? reference : nil) { return .failed(problem) }
            return .recorded(written: written.path)
        }
        if old == png { return .matched }
        guard let detail = compare(png, old) else { return .matched }
        if let problem = write(png, to: written, alsoTo: record ? reference : nil) { return .failed(problem) }
        return .differs(detail, written: written.path)
    }

    /// The PNG of `view` drawn at `size` points, 2 pixels per point, on the window background of `appearance`.
    public static func render<V: View>(_ view: V, size: CGSize, appearance: SnapshotAppearance) -> Data? {
        let appearanceObject = NSAppearance(named: appearance.name)
        let root = view
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, appearance == .dark ? .dark : .light)
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(origin: .zero, size: size)
        host.appearance = appearanceObject
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = appearanceObject
        window.contentView = host
        defer { window.close() }
        // Let SwiftUI apply its updates and AppKit lay out the hosted controls.
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()

        let scale = 2.0
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                            pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                            hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        bitmap.size = size
        var drawn: Data?
        appearanceObject?.performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            drawn = bitmap.representation(using: .png, properties: [:])
        }
        return drawn
    }

    /// Nil when two PNGs show the same picture: the same size, and no more than 0.1 % of the pixels with a channel more
    /// than 8 of 255 apart (anti-aliased text edges move by a few counts between runs of the same image). Else what differs.
    public static func compare(_ new: Data, _ old: Data) -> String? {
        guard let a = pixels(new), let b = pixels(old) else { return "a picture does not decode" }
        guard a.width == b.width, a.height == b.height else {
            return "size \(a.width) x \(a.height) px, reference \(b.width) x \(b.height) px"
        }
        var differing = 0
        for pixel in 0 ..< a.width * a.height {
            for channel in 0 ..< 4 where abs(Int(a.bytes[pixel * 4 + channel]) - Int(b.bytes[pixel * 4 + channel])) > 8 {
                differing += 1
                break
            }
        }
        let allowed = a.width * a.height / 1000
        return differing <= allowed ? nil : "\(differing) of \(a.width * a.height) pixels differ, \(allowed) allowed"
    }

    private static func pixels(_ png: Data) -> (width: Int, height: Int, bytes: [UInt8])? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? (width, height, bytes) : nil
    }

    /// Writes `png` to `url` (and to `also` when set); nil on success, else why not.
    private static func write(_ png: Data, to url: URL, alsoTo also: URL?) -> String? {
        do {
            for target in [url, also].compactMap({ $0 }) {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try png.write(to: target)
            }
            return nil
        } catch {
            return "could not write \(url.path): \(error.localizedDescription)"
        }
    }
}
