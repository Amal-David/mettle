import XCTest
@testable import MettlePreview

final class PlaybackTests: XCTestCase {
    func testStartsPausedAndEmpty() {
        let c = PlaybackClock(); XCTAssertEqual(c.position, 0); XCTAssertFalse(c.isPlaying)
    }
    func testZeroDurationCannotPlay() {
        var c = PlaybackClock(); c.play(at: 10); XCTAssertFalse(c.isPlaying)
    }
    func testPlayPauseResumeHasNoJump() {
        var c = PlaybackClock(duration: 4); c.play(at: 10); c.pause(at: 11)
        XCTAssertEqual(c.position, 1); c.play(at: 500); c.advance(to: 500.5)
        XCTAssertEqual(c.position, 1.5)
    }
    func testSeekClampsAndPauses() {
        var c = PlaybackClock(duration: 4); c.play(at: 0); c.seek(to: 99)
        XCTAssertEqual(c.position, 4); XCTAssertFalse(c.isPlaying)
        c.seek(to: -5); XCTAssertEqual(c.position, 0)
    }
    func testOnceStopsAtEndAndReplayStartsAtZero() {
        var c = PlaybackClock(duration: 2); c.play(at: 0); c.advance(to: 3)
        XCTAssertEqual(c.position, 2); XCTAssertFalse(c.isPlaying)
        c.play(at: 10); XCTAssertEqual(c.position, 0); XCTAssertTrue(c.isPlaying)
    }
    func testLoopPreservesOvershoot() {
        var c = PlaybackClock(duration: 2, repetition: .loop); c.play(at: 0); c.advance(to: 6.25)
        XCTAssertEqual(c.position, 0.25); XCTAssertTrue(c.isPlaying)
    }
    func testPingPongReverses() {
        var c = PlaybackClock(duration: 2, repetition: .pingPong); c.play(at: 0)
        c.advance(to: 2.5); XCTAssertEqual(c.position, 1.5)
        c.advance(to: 4.25); XCTAssertEqual(c.position, 0.25)
    }
    func testSpeedChangeIsContinuous() {
        var c = PlaybackClock(duration: 10); c.play(at: 0)
        c.setSpeed(2, at: 1); XCTAssertEqual(c.position, 1)
        c.advance(to: 2); XCTAssertEqual(c.position, 3)
    }
    func testInvalidInputsDoNotPoisonPlayback() {
        var c = PlaybackClock(duration: 4); c.play(at: 0); c.seek(to: .nan)
        c.setSpeed(.infinity, at: 0); c.advance(to: .nan); c.advance(to: 1)
        XCTAssertEqual(c.position, 1); XCTAssertEqual(c.speed, 1)
    }
    func testBackwardsClockCannotReverseAnimation() {
        var c = PlaybackClock(duration: 4); c.play(at: 5); c.advance(to: 4)
        XCTAssertEqual(c.position, 0)
        c.advance(to: 5); XCTAssertEqual(c.position, 0)
        c.advance(to: 5.5); XCTAssertEqual(c.position, 0.5)
    }
    func testChangingRepeatModeOnReturnLegKeepsVisiblePlayhead() {
        var c = PlaybackClock(duration: 2, repetition: .pingPong)
        c.play(at: 0); c.advance(to: 3); XCTAssertEqual(c.position, 1)
        c.repetition = .once; c.advance(to: 3.25)
        XCTAssertEqual(c.position, 1.25); XCTAssertTrue(c.isPlaying)
    }
    func testScrubShowsExactEndpointForLoop() {
        var c = PlaybackClock(duration: 4, repetition: .loop); c.seek(to: 4)
        XCTAssertEqual(c.position, 4); XCTAssertFalse(c.isPlaying)
    }
}
