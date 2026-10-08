import Foundation

/// The preview's single source of truth for both the playhead and rendered time.
/// Independent of wall-clock dates and SwiftUI, so seeking and looping are testable.
public struct PlaybackClock {
    public enum Repetition: String { case once, loop, pingPong }
    public private(set) var duration: Double
    public private(set) var position: Double = 0
    public private(set) var isPlaying = false
    public var repetition: Repetition {
        didSet {
            // A ping-pong return phase can be greater than the visible duration.
            // Changing repeat mode must continue at the visible playhead.
            if repetition != oldValue { phase = position }
        }
    }
    public private(set) var speed: Double = 1
    private var phase: Double = 0
    private var lastTick: Double?

    public init(duration: Double = 0, repetition: Repetition = .once) {
        self.duration = duration.isFinite ? max(0, duration) : 0
        self.repetition = repetition
    }
    public mutating func play(at now: Double) {
        guard duration > 0, now.isFinite else { return }
        if position >= duration && repetition == .once { phase = 0; position = 0 }
        lastTick = now; isPlaying = true
    }
    public mutating func pause(at now: Double? = nil) {
        if let now { advance(to: now) }
        isPlaying = false; lastTick = nil
    }
    public mutating func seek(to value: Double) {
        guard value.isFinite else { return }
        position = min(duration, max(0, value)); phase = position
        isPlaying = false; lastTick = nil
    }
    public mutating func setSpeed(_ value: Double, at now: Double) {
        guard value.isFinite, (0.25...2).contains(value) else { return }
        advance(to: now); speed = value
    }
    public mutating func advance(to now: Double) {
        guard isPlaying, now.isFinite, duration > 0 else { return }
        guard let previous = lastTick else { lastTick = now; return }
        guard now >= previous else { return }
        let delta = now - previous
        lastTick = now
        phase += delta * speed
        switch repetition {
        case .once:
            position = min(duration, phase)
            if position >= duration { isPlaying = false; lastTick = nil }
        case .loop:
            phase = phase.truncatingRemainder(dividingBy: duration)
            position = phase
        case .pingPong:
            phase = phase.truncatingRemainder(dividingBy: duration * 2)
            position = phase <= duration ? phase : duration * 2 - phase
        }
    }
}
