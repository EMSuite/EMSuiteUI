import AppKit
import RealityKit
import SwiftUI
import simd

// Arguments: --cells N (Si block N x N x N; 4 gives 559 atoms, 14 gives 15 863) --mode instanced|entities
// --lighting studio|plain --appearance light|dark --bench SECONDS (0 = interactive) --out DIR --tag NAME --camscale F
struct SpikeArgs {
    var cells = 4, mode = SpikeStage.Mode.instanced, lighting = SpikeStage.Lighting.studio
    var dark = true, bench = 10.0, out = URL(fileURLWithPath: NSTemporaryDirectory()), tag = "run", camScale: Float = 1.0
    init() {
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
            let v = it.next() ?? ""
            switch k {
            case "--cells": cells = Int(v) ?? cells
            case "--mode": mode = SpikeStage.Mode(rawValue: v) ?? mode
            case "--lighting": lighting = SpikeStage.Lighting(rawValue: v) ?? lighting
            case "--appearance": dark = (v != "light")
            case "--bench": bench = Double(v) ?? bench
            case "--out": out = URL(fileURLWithPath: v)
            case "--tag": tag = v
            case "--camscale": camScale = Float(v) ?? camScale
            default: break
            }
        }
    }
}

@MainActor
final class SpikeModel: ObservableObject {
    let args = SpikeArgs()
    let scene: SpikeScene
    var built: SpikeStage.Built?
    var buildMs = 0.0
    let base: simd_quatf
    var dragStart = simd_quatf(angle: 0, axis: [0, 0, 1])
    var current: simd_quatf
    var subscription: EventSubscription?
    // bench
    var clock = 0.0
    var deltas: [Double] = []
    var finished = false
    @Published var status = ""

    init() {
        scene = SpikeGeometry.silicon(args.cells, args.cells, args.cells)
        base = simd_quatf(SpikeGeometry.zoneAxisRotation([1, 1, 0], up: [0, 0, 1]))
        current = base
    }

    var cameraScale: Float { (built?.extent ?? 0.3) * 0.62 * args.camScale }

    func make(_ content: inout RealityViewCameraContent) {
        let t0 = Date()
        do {
            let b = try SpikeStage.build(scene, mode: args.mode, lighting: args.lighting)
            built = b
            b.pivot.orientation = base
            content.add(b.root)
            content.add(SpikeStage.camera(scale: cameraScale))
        } catch {
            status = "build failed: \(error)"
            return
        }
        buildMs = Date().timeIntervalSince(t0) * 1000
        status = "\(scene.atoms.count) atoms, \(scene.bonds.count) bonds, \(args.mode.rawValue), built in \(Int(buildMs)) ms"
        guard args.bench > 0 else { return }
        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            MainActor.assumeIsolated { self?.tick(event.deltaTime) }
        }
    }

    /// Turns the crystal as a slow drag would: a tilt of up to 15° that wanders around the beam.
    func tick(_ dt: TimeInterval) {
        guard !finished, let pivot = built?.pivot else { return }
        clock += dt
        let warm = 2.0
        if clock > warm { deltas.append(dt) }
        let s = Float(clock)
        let tx = simd_quatf(angle: 15 * .pi / 180 * sin(2 * .pi * 0.31 * s), axis: [1, 0, 0])
        let ty = simd_quatf(angle: 15 * .pi / 180 * cos(2 * .pi * 0.23 * s), axis: [0, 1, 0])
        current = tx * ty * base
        pivot.orientation = current
        if clock > warm + args.bench {
            finished = true
            Task { await self.finish() }
        }
    }

    func finish() async {
        let hz = NSScreen.main?.maximumFramesPerSecond ?? 0
        let ms = deltas.map { $0 * 1000 }.sorted()
        func pct(_ p: Double) -> Double { ms.isEmpty ? .nan : ms[min(ms.count - 1, Int(Double(ms.count) * p))] }
        let over = ms.filter { $0 > 16.7 }.count
        let overInterval = hz > 0 ? ms.filter { $0 > 1.5 * 1000 / Double(hz) }.count : -1
        let fm = { (x: Double) in String(format: "%.2f", x) }
        var line = "SPIKE|tag=\(args.tag)|atoms=\(scene.atoms.count)|bonds=\(scene.bonds.count)|mode=\(args.mode.rawValue)"
        line += "|lighting=\(args.lighting.rawValue)|appearance=\(args.dark ? "dark" : "light")|display_hz=\(hz)"
        line += "|frames=\(ms.count)|p50_ms=\(fm(pct(0.5)))|p95_ms=\(fm(pct(0.95)))|p99_ms=\(fm(pct(0.99)))|max_ms=\(fm(ms.last ?? .nan))"
        line += "|over_16.7ms=\(over)|over_1.5_intervals=\(overInterval)|build_ms=\(fm(buildMs))"
        // the window as the person sees it
        try? FileManager.default.createDirectory(at: args.out, withIntermediateDirectories: true)
        if let w = NSApp.windows.first(where: { $0.isVisible }) {
            let shot = args.out.appendingPathComponent("\(args.tag)-window.png").path
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-x", "-o", "-l\(w.windowNumber)", shot]
            try? p.run(); p.waitUntilExit()
            line += "|window_png=\(FileManager.default.fileExists(atPath: shot) ? "yes" : "no")"
        }
        // the still mode, offscreen
        if let b = built {
            let url = args.out.appendingPathComponent("\(args.tag)-still.png")
            do {
                let s = try await SpikeOffscreen.render(b, rotation: base, cameraScale: cameraScale, size: 1024,
                                                        background: CGColor(srgbRed: 0.10, green: 0.105, blue: 0.115, alpha: 1), to: url)
                line += "|still_ms=\(fm(s * 1000))"
            } catch { line += "|still_error=\(error)" }
        }
        print(line)
        let res = args.out.appendingPathComponent("results.txt")
        if let h = try? FileHandle(forWritingTo: res) { h.seekToEndOfFile(); h.write((line + "\n").data(using: .utf8)!); try? h.close() }
        else { try? (line + "\n").write(to: res, atomically: true, encoding: .utf8) }
        let raw = ms.map { fm($0) }.joined(separator: "\n")
        try? raw.write(to: args.out.appendingPathComponent("\(args.tag)-frames-ms.txt"), atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    // Interactive drag (only when --bench 0): the orientation is view state during the drag, as MU1 will do it.
    func drag(_ v: DragGesture.Value, ended: Bool) {
        guard let pivot = built?.pivot else { return }
        let k: Float = .pi / 400   // 400 pt = 180°
        let dx = Float(v.translation.width), dy = Float(v.translation.height)
        let q: simd_quatf
        if NSEvent.modifierFlags.contains(.option) {
            q = simd_quatf(angle: -dx * k, axis: [0, 0, 1])
        } else {
            q = simd_quatf(angle: dx * k, axis: [0, 1, 0]) * simd_quatf(angle: dy * k, axis: [1, 0, 0])
        }
        current = q * dragStart
        pivot.orientation = current
        if ended { dragStart = current }
    }
}

struct SpikeView: View {
    @StateObject var model = SpikeModel()
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Si [110]").font(.headline)
                Text("Fd-3m · a 5.4309 Å · RealityKit spike (MU0)").foregroundStyle(.secondary)
            }
            Text("Crystal · seen down [110]").font(.callout).foregroundStyle(.secondary)
            ZStack(alignment: .topTrailing) {
                RealityView { content in
                    model.make(&content)
                }
                .background(Color(red: 0.10, green: 0.105, blue: 0.115))
                .gesture(DragGesture(minimumDistance: 1)
                    .onChanged { model.drag($0, ended: false) }
                    .onEnded { model.drag($0, ended: true) })
                HStack(spacing: 6) {
                    Circle().fill(Color(nsColor: SpikeStage.siliconColor)).frame(width: 10, height: 10)
                    Text("Si").font(.callout)
                }
                .padding(6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(width: 720, height: 720)
            Text(model.status).font(.callout).foregroundStyle(.secondary)
        }
        .padding(16)
    }
}

@main
struct CrystalSpikeApp: App {
    init() {
        let dark = SpikeArgs().dark
        NSApplication.shared.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }
    var body: some Scene {
        WindowGroup("Crystal spike") { SpikeView() }
            .windowResizability(.contentSize)
    }
}
