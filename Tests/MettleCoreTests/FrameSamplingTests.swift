import XCTest
@testable import MettleCore

final class FrameSamplingTests: XCTestCase {
    func testExactSourceEndpointIsNotRoundedToAFPSGrid() throws {
        let times = try FrameSampling.explicit("0, 0.125,0.20000000298023224")
        XCTAssertEqual(times, [0, 0.125, 0.20000000298023224])
    }
    func testInvalidAndAmbiguousSchedulesAreRejected() {
        for text in ["", "0,", "0,0", "1,0", "nan", "inf", "-1", "86401", "0,nope"] {
            XCTAssertThrowsError(try FrameSampling.explicit(text), text)
        }
    }
    func testRegularScheduleUsesAbsoluteStartWithoutCumulativeDrift() throws {
        let times = try FrameSampling.regular(fps: 30, start: 0.25, duration: 1, count: 24)
        XCTAssertEqual(times.first, 0.25)
        XCTAssertEqual(times.last, 0.25 + 23.0 / 30.0)
        XCTAssertEqual(times.count, 24)
    }
    func testRegularLimitsFailBeforeAllocatingFrames() {
        XCTAssertThrowsError(try FrameSampling.regular(fps: 0, start: 0, duration: 1))
        XCTAssertThrowsError(try FrameSampling.regular(fps: 30, start: -.infinity, duration: 1))
        XCTAssertThrowsError(try FrameSampling.regular(fps: 120, start: 0, duration: 1000))
        XCTAssertThrowsError(try FrameSampling.regular(fps: 30, start: 86400, duration: 1, count: 2))
    }
}
