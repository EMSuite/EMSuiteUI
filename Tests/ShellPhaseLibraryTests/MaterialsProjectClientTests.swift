//
//  MaterialsProjectClientTests.swift
//  EMSuiteUI#188: the client's manners, all on a stub transport (no network in any test).
//

import Foundation
import XCTest
@testable import ShellPhaseLibrary

/// Records what was sent and answers from a script.
final class StubTransport: PhaseTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _sent: [URLRequest] = []
    var answer: @Sendable (URLRequest) throws -> (Data, Int, [String: String])

    init(answer: @escaping @Sendable (URLRequest) throws -> (Data, Int, [String: String]) = { _ in (Data("{}".utf8), 200, [:]) }) {
        self.answer = answer
    }

    var sent: [URLRequest] { lock.withLock { _sent } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { _sent.append(request) }
        let (data, status, headers) = try answer(request)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }
}

/// A clock the sleeps move forward, so a test never waits.
final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t = Date(timeIntervalSince1970: 1_795_000_000)
    private var _slept: [Duration] = []
    var now: Date { lock.withLock { t } }
    var slept: [Duration] { lock.withLock { _slept } }
    func advance(_ seconds: TimeInterval) { lock.withLock { t += seconds } }
    func sleep(_ d: Duration) { lock.withLock { _slept.append(d); t += Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18 } }
}

/// Holds the first typing pause until the test opens it; every later pause passes at once.
final class PauseGate: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var paused = false
    private var opened = false
    private var pausedWaiter: CheckedContinuation<Void, Never>?
    private var openWaiter: CheckedContinuation<Void, Never>?

    func pause() async {
        let first = lock.withLock { () -> Bool in calls += 1; return calls == 1 }
        guard first else { return }
        lock.withLock { () -> CheckedContinuation<Void, Never>? in
            paused = true; defer { pausedWaiter = nil }; return pausedWaiter
        }?.resume()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let go = lock.withLock { () -> Bool in if opened { return true }; openWaiter = c; return false }
            if go { c.resume() }
        }
    }

    func waitUntilTheFirstPauses() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let go = lock.withLock { () -> Bool in if paused { return true }; pausedWaiter = c; return false }
            if go { c.resume() }
        }
    }

    func open() {
        lock.withLock { () -> CheckedContinuation<Void, Never>? in
            opened = true; defer { openWaiter = nil }; return openWaiter
        }?.resume()
    }
}

final class MaterialsProjectClientTests: XCTestCase {
    private let r1 = URLRequest(url: URL(string: "https://optimade.materialsproject.org/v1/structures?filter=elements%20HAS%20%22Si%22")!)
    private let r2 = URLRequest(url: URL(string: "https://optimade.materialsproject.org/v1/structures?filter=elements%20HAS%20%22Al%22")!)

    private func client(_ transport: StubTransport, _ clock: FakeClock) -> MaterialsProjectClient {
        MaterialsProjectClient(transport: transport, now: { clock.now }, sleep: { clock.sleep($0) })
    }

    func testASearchWaitsTheTypingPauseAndIsAnsweredFromMemoryForADay() async throws {
        let transport = StubTransport(), clock = FakeClock()
        let c = client(transport, clock)
        _ = try await c.search(r1, key: nil)
        XCTAssertEqual(clock.slept.first, .milliseconds(350))
        _ = try await c.search(r1, key: nil)
        XCTAssertEqual(transport.sent.count, 1, "the same search within a day is not sent again")
        clock.advance(24 * 3600)
        _ = try await c.search(r1, key: nil)
        XCTAssertEqual(transport.sent.count, 2, "after a day it is")
    }

    func testAtMostTwoRequestsASecond() async throws {
        let transport = StubTransport(), clock = FakeClock()
        let c = client(transport, clock)
        let start = clock.now
        _ = try await c.download(r1, key: nil)
        _ = try await c.download(r2, key: nil)
        _ = try await c.download(r1, key: nil)
        XCTAssertEqual(transport.sent.count, 3)
        XCTAssertGreaterThanOrEqual(clock.now.timeIntervalSince(start), 1.0, "three sends take at least a second")
    }

    func testTheKeyGoesInItsHeaderOnlyAndTheTimeoutsAreSet() async throws {
        let transport = StubTransport(), clock = FakeClock()
        let c = client(transport, clock)
        _ = try await c.search(r1, key: "secret")
        _ = try await c.download(r2, key: nil)
        XCTAssertEqual(transport.sent[0].value(forHTTPHeaderField: "X-API-KEY"), "secret")
        XCTAssertEqual(transport.sent[0].timeoutInterval, 15)
        XCTAssertEqual(transport.sent[0].cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertNil(transport.sent[1].value(forHTTPHeaderField: "X-API-KEY"))
        XCTAssertEqual(transport.sent[1].timeoutInterval, 30)
        XCTAssertFalse(MaterialsProjectClient.cacheKey(r1, key: "secret").contains("secret"), "the cache never holds the key")
    }

    func testOfflineIsSaidAtOnceAndTheServicesRefusalsAreNamed() async {
        let clock = FakeClock()
        let offline = client(StubTransport { _ in throw URLError(.notConnectedToInternet) }, clock)
        do { _ = try await offline.download(r1, key: nil); XCTFail("no error") } catch { XCTAssertEqual(error as? MaterialsProjectClient.Failure, .offline) }
        let refused = client(StubTransport { _ in (Data(), 401, [:]) }, clock)
        do { _ = try await refused.download(r1, key: "bad"); XCTFail("no error") } catch { XCTAssertEqual(error as? MaterialsProjectClient.Failure, .keyRefused) }
        let busy = client(StubTransport { _ in (Data(), 429, ["Retry-After": "3"]) }, clock)
        do { _ = try await busy.download(r1, key: nil); XCTFail("no error") } catch { XCTAssertEqual(error as? MaterialsProjectClient.Failure, .busy(retryAfter: 3)) }
    }

    /// One search in flight: a search typed while an earlier one is still pausing supersedes it, and only the newer is sent.
    /// No timing: the first pause holds until the second search has been sent.
    func testANewerSearchSupersedesOneStillPausing() async throws {
        let transport = StubTransport()
        let gate = PauseGate()
        let c = MaterialsProjectClient(transport: transport, sleep: { d in
            if d == MaterialsProjectClient.typingPause { await gate.pause() }
        })
        let (one, two) = (r1, r2)   // the tasks capture the requests, not the test case
        let first = Task { try await c.search(one, key: nil) }
        await gate.waitUntilTheFirstPauses()
        _ = try await c.search(two, key: nil)
        gate.open()
        do { _ = try await first.value; XCTFail("the first search was not superseded") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(transport.sent.map(\.url), [r2.url])
    }

    /// The app's own transport writes nothing to the system's cache and does not wait for a network.
    func testTheSessionKeepsNothingAndDoesNotWait() {
        _ = URLSessionPhaseTransport()
        XCTAssertEqual(MaterialsProjectClient.searchTimeout, 15)
        XCTAssertEqual(MaterialsProjectClient.downloadTimeout, 30)
    }
}

final class APIKeyStoreTests: XCTestCase {
    /// The same item 4DSTEM Studio has used, so a key saved there is found here.
    func testTheKeyStaysWhereFourDSTEMStudioKeepsIt() {
        XCTAssertEqual(KeychainAPIKeyStore.defaultService, "com.mac4dstem.materials-project")
        XCTAssertEqual(KeychainAPIKeyStore.defaultAccount, "api-key")
    }
}
