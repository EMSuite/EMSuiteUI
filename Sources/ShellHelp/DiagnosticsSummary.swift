//
//  DiagnosticsSummary.swift
//  Role: the few facts a problem report needs to name its build and its Mac: the app's version and build, where it came from (the
//        website or the App Store), macOS, the Mac's model and its memory. Read on this Mac and shown to the person before any of it
//        leaves (`FeedbackComposer`, `FeedbackView`); nothing about their files, their data or their use is in it.
//

import Darwin
import Foundation

/// Where this copy of the app came from. The app knows (each app's build settings say which build it is) and passes it in.
public nonisolated enum DistributionChannel: String, Sendable, CaseIterable {
    case website, appStore, development

    public var title: String {
        switch self {
        case .website: "website"
        case .appStore: "App Store"
        case .development: "development build"
        }
    }
}

public nonisolated struct DiagnosticsSummary: Equatable, Sendable {
    public var appName: String
    /// "2.3.0 (52)": the marketing version and the build.
    public var appVersion: String
    public var channel: DistributionChannel
    /// "26.1.0".
    public var macOSVersion: String
    /// The model identifier, "Mac16,7"; "unknown" when the system does not say.
    public var macModel: String
    public var memoryBytes: UInt64

    public init(appName: String, appVersion: String, channel: DistributionChannel, macOSVersion: String, macModel: String, memoryBytes: UInt64) {
        self.appName = appName; self.appVersion = appVersion; self.channel = channel
        self.macOSVersion = macOSVersion; self.macModel = macModel; self.memoryBytes = memoryBytes
    }

    /// This Mac and this app, read now.
    public static func current(appName: String, channel: DistributionChannel, bundle: Bundle = .main) -> DiagnosticsSummary {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return DiagnosticsSummary(appName: appName, appVersion: version(of: bundle), channel: channel,
                                  macOSVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                                  macModel: sysctlString("hw.model") ?? "unknown",
                                  memoryBytes: ProcessInfo.processInfo.physicalMemory)
    }

    /// "2.3.0 (52)" from the bundle; "unknown" for a bundle without a version (a test host).
    public static func version(of bundle: Bundle) -> String {
        let info = bundle.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String else { return "unknown" }
        guard let build = info?["CFBundleVersion"] as? String, build != version else { return version }
        return "\(version) (\(build))"
    }

    /// The memory in whole gigabytes, as the Mac's About window states it ("36 GB").
    public var memoryText: String { "\(memoryBytes / (1 << 30)) GB" }

    /// The summary as lines a person reads and a report carries, in a fixed order.
    public var lines: [String] {
        [
            "\(appName) \(appVersion) (\(channel.title))",
            "macOS \(macOSVersion)",
            "Mac \(macModel), \(memoryText) memory",
        ]
    }

    public var text: String { lines.joined(separator: "\n") }

    /// A string value of `sysctlbyname`, nil when the name is unknown.
    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        let value = String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return value.isEmpty ? nil : value
    }
}
