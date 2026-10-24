import Foundation

public struct LatencyStats: Codable, Sendable, Equatable {
    public let count: Int
    public let median: Double?
    public let p90: Double?
    public let max: Double?

    public init(samples: [Double]) {
        let sorted = samples.sorted()
        count = sorted.count
        median = Self.percentile(sorted, 0.5)
        p90 = Self.percentile(sorted, 0.9)
        max = sorted.last
    }

    /// Nearest-rank percentile on pre-sorted samples.
    static func percentile(_ sorted: [Double], _ p: Double) -> Double? {
        guard !sorted.isEmpty else { return nil }
        let rank = Int((p * Double(sorted.count)).rounded(.up))
        return sorted[Swift.min(Swift.max(rank, 1), sorted.count) - 1]
    }
}
