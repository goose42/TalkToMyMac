/// Average and tail latency over a set of dictations.
public struct LatencySummary: Equatable, Sendable {
    public let sampleCount: Int
    public let mean: Double
    public let p99: Double

    public init(sampleCount: Int, mean: Double, p99: Double) {
        self.sampleCount = sampleCount
        self.mean = mean
        self.p99 = p99
    }
}

/// Latency statistics for the Instrumentation tab.
public enum LatencyStats {

    /// Latency per unit of work (per word, per audio second), weighted by each sample's
    /// size, so short dictations — which carry a larger share of fixed overhead — count in
    /// proportion to how much work they contained rather than one vote each.
    ///
    /// - `mean` is total time ÷ total units (equivalently, the unit-weighted mean of each
    ///   sample's rate).
    /// - `p99` is the unit-weighted 99th percentile of per-sample rates: the rate that 99%
    ///   of all *units* processed came in at or under.
    ///
    /// Samples with no units (e.g. a dictation with zero words) are skipped, since they have
    /// no defined rate. Returns nil if nothing remains.
    public static func perUnit(_ samples: [(time: Double, units: Double)]) -> LatencySummary? {
        let valid = samples.filter { $0.units > 0 }
        guard !valid.isEmpty else { return nil }

        let totalTime = valid.reduce(0) { $0 + $1.time }
        let totalUnits = valid.reduce(0) { $0 + $1.units }
        let rates = valid.map { (value: $0.time / $0.units, weight: $0.units) }

        return LatencySummary(
            sampleCount: valid.count,
            mean: totalTime / totalUnits,
            p99: weightedPercentile(rates, 0.99)
        )
    }

    /// Plain per-dictation latency: every sample counts equally.
    public static func perSample(_ times: [Double]) -> LatencySummary? {
        guard !times.isEmpty else { return nil }
        return LatencySummary(
            sampleCount: times.count,
            mean: times.reduce(0, +) / Double(times.count),
            p99: weightedPercentile(times.map { ($0, 1) }, 0.99)
        )
    }

    /// Smallest value whose cumulative weight reaches `p` of the total weight (the
    /// nearest-rank method, generalised to weights). With equal weights this is the
    /// classic nearest-rank percentile.
    static func weightedPercentile(_ values: [(value: Double, weight: Double)], _ p: Double) -> Double {
        let sorted = values.sorted { $0.value < $1.value }
        let threshold = p * sorted.reduce(0) { $0 + $1.weight }
        var cumulative = 0.0
        for entry in sorted {
            cumulative += entry.weight
            if cumulative >= threshold { return entry.value }
        }
        return sorted.last?.value ?? 0
    }
}
