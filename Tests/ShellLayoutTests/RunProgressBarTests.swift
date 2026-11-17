// The infobar's run bar draws the value it is given (4DSTEM-Studio#445: the system bar animated every update and trailed
// the count).

import XCTest
@testable import ShellLayout

nonisolated final class RunProgressBarTests: XCTestCase {

    /// The fill covers the progress's share of the track, clamped to the track; a value that is not finite draws none.
    /// Mutation: the fill not clamped (1.4 overdraws the track) or NaN passed through - red.
    func testTheFillIsTheProgressClampedToTheTrack() {
        XCTAssertEqual(RunProgressBar.fillFraction(0), 0)
        XCTAssertEqual(RunProgressBar.fillFraction(0.915), 0.915)
        XCTAssertEqual(RunProgressBar.fillFraction(1), 1)
        XCTAssertEqual(RunProgressBar.fillFraction(1.4), 1)
        XCTAssertEqual(RunProgressBar.fillFraction(-0.2), 0)
        XCTAssertEqual(RunProgressBar.fillFraction(.nan), 0)
        XCTAssertEqual(RunProgressBar.fillFraction(.infinity), 0)
    }
}
