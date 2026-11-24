//
//  MaterialsProjectClient.swift
//  Role: the one way the apps talk to the Materials Project (EMSuiteUI#188, plan section 5.2). It sends what DiffractoKit's
//        request builders make and hands back the bytes for the kit's decoders; it builds and reads nothing itself. A polite
//        client: one search in flight (a newer one supersedes it), a 350 ms pause after typing, at most two requests a second
//        (the service allows 25), a search answered from memory for 24 hours, 15 s for a search and 30 s for a download, an
//        immediate "offline" with no waiting for the network, and nothing written to the system's URL cache. The person's key,
//        when there is one, goes in the X-API-KEY header and nowhere else.
//

import Foundation

/// Sends one request; the tests give a stub, the app `URLSessionPhaseTransport`.
public nonisolated protocol PhaseTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The app's transport: an ephemeral session (no cookies, no disk cache) that does not wait for connectivity.
public nonisolated final class URLSessionPhaseTransport: PhaseTransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = MaterialsProjectClient.searchTimeout
        configuration.timeoutIntervalForResource = MaterialsProjectClient.downloadTimeout
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MaterialsProjectClient.Failure.notHTTP }
        return (data, http)
    }
}

public actor MaterialsProjectClient {
    public nonisolated static let searchTimeout: TimeInterval = 15
    public nonisolated static let downloadTimeout: TimeInterval = 30
    public nonisolated static let typingPause: Duration = .milliseconds(350)
    /// Two requests a second at most.
    public nonisolated static let minimumInterval: TimeInterval = 0.5
    public nonisolated static let cacheLifetime: TimeInterval = 24 * 3600
    /// The most search answers kept in memory.
    nonisolated static let cacheCapacity = 200
    public nonisolated static let keyHeader = "X-API-KEY"

    /// What went wrong, in the words the sheet shows. A newer search superseding this one is `CancellationError`, not a failure.
    public nonisolated enum Failure: Error, Equatable, Sendable {
        /// No network: said at once, never waited out.
        case offline
        case timedOut
        /// The service refused the key (401 or 403).
        case keyRefused
        /// Too many requests (429), with the seconds the service asked for when it said.
        case busy(retryAfter: TimeInterval?)
        case status(Int)
        case notHTTP
    }

    private struct Cached { let data: Data; let stored: Date }

    private let transport: any PhaseTransport
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private var cache: [String: Cached] = [:]
    /// The earliest time the next request may go.
    private var nextSend: Date?
    private var generation = 0

    public init(transport: any PhaseTransport = URLSessionPhaseTransport(),
                now: @escaping @Sendable () -> Date = Date.init,
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.transport = transport; self.now = now; self.sleep = sleep
    }

    /// A search as the person types: waits the typing pause, and gives up (`CancellationError`) when a newer search came in
    /// meanwhile, so only the last one is sent. Answered from memory when the same request was answered in the last 24 hours.
    public func search(_ request: URLRequest, key: String?) async throws -> Data {
        generation += 1
        let mine = generation
        try await sleep(Self.typingPause)
        guard mine == generation else { throw CancellationError() }
        let id = Self.cacheKey(request, key: key)
        if let hit = cache[id], now().timeIntervalSince(hit.stored) < Self.cacheLifetime { return hit.data }
        let data = try await send(request, key: key, timeout: Self.searchTimeout)
        // A search that a newer one superseded while it was on the wire is not shown, but its answer is kept.
        let stored = now()
        // Answers past their day are dropped here, and the oldest past `cacheCapacity`, so a long session does not keep them all.
        cache = cache.filter { stored.timeIntervalSince($0.value.stored) < Self.cacheLifetime }
        if cache.count >= Self.cacheCapacity, let oldest = cache.min(by: { $0.value.stored < $1.value.stored })?.key {
            cache[oldest] = nil
        }
        cache[id] = Cached(data: data, stored: stored)
        guard mine == generation else { throw CancellationError() }
        return data
    }

    /// One structure's download, after the person chose it: no typing pause, never cached (the library keeps the result).
    public func download(_ request: URLRequest, key: String?) async throws -> Data {
        try await send(request, key: key, timeout: Self.downloadTimeout)
    }

    /// Forgets every cached search (a new key changes what the service answers).
    public func clearCache() { cache.removeAll() }

    private func send(_ request: URLRequest, key: String?, timeout: TimeInterval) async throws -> Data {
        // The send's time is taken before the wait: two sends that arrive together get two slots, not the same one.
        let arrived = now()
        let slot = nextSend.map { max($0, arrived) } ?? arrived
        nextSend = slot.addingTimeInterval(Self.minimumInterval)
        let wait = slot.timeIntervalSince(arrived)
        if wait > 0 { try await sleep(.milliseconds(Int((wait * 1000).rounded(.up)))) }
        let prepared = Self.prepared(request, key: key, timeout: timeout)
        let data: Data, response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(prepared)
        } catch let error as URLError {
            throw Self.failure(for: error)
        }
        switch response.statusCode {
        case 200..<300: return data
        case 401, 403: throw Failure.keyRefused
        case 429: throw Failure.busy(retryAfter: response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init))
        default: throw Failure.status(response.statusCode)
        }
    }

    /// The request as sent: the timeout, no cached answer, and the key in its header when there is one.
    nonisolated static func prepared(_ request: URLRequest, key: String?, timeout: TimeInterval) -> URLRequest {
        var r = request
        r.timeoutInterval = timeout
        r.cachePolicy = .reloadIgnoringLocalCacheData
        if let key, !key.isEmpty { r.setValue(key, forHTTPHeaderField: keyHeader) } else { r.setValue(nil, forHTTPHeaderField: keyHeader) }
        return r
    }

    /// The cache tells a keyed search from a keyless one, without keeping the key.
    nonisolated static func cacheKey(_ request: URLRequest, key: String?) -> String {
        ((key?.isEmpty ?? true) ? "open " : "keyed ") + (request.url?.absoluteString ?? "")
    }

    nonisolated static func failure(for error: URLError) -> Failure {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .dataNotAllowed, .internationalRoamingOff:
            .offline
        case .timedOut: .timedOut
        default: .status(error.errorCode)
        }
    }
}
