import Foundation

/// Input levels over capture time. Written from the audio thread, read from the main actor.
public final class LevelTimeline: @unchecked Sendable {
    private struct Sample {
        let time: Double
        let db: Double
    }

    private let lock = NSLock()
    private var samples: [Sample] = []

    public init() {}

    public func append(time: Double, db: Double) {
        lock.lock()
        samples.append(Sample(time: time, db: db))
        lock.unlock()
    }

    /// Mean of samples whose time falls in `start...end`, or nil if none do.
    public func meanDB(from start: Double, to end: Double) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        let window = samples.filter { $0.time >= start && $0.time <= end }
        guard !window.isEmpty else { return nil }
        return window.reduce(0) { $0 + $1.db } / Double(window.count)
    }

    public func reset() {
        lock.lock()
        samples.removeAll()
        lock.unlock()
    }

    /// RMS of float samples as dBFS, floored at -120.
    public static func rmsDB(_ values: UnsafeBufferPointer<Float>) -> Double {
        guard !values.isEmpty else { return -120 }
        let sumSquares = values.reduce(Float(0)) { $0 + $1 * $1 }
        let rms = (sumSquares / Float(values.count)).squareRoot()
        return rms > 0 ? max(20 * log10(Double(rms)), -120) : -120
    }
}
