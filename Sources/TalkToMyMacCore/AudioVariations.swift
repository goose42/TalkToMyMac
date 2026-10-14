import Foundation

/// Synthetic variations of a recording, for finding what else the speech engine might hear
/// in it. These are the usual speech-recognition augmentations: speed perturbation, a
/// phone-quality band limit, background noise and (via `PitchShifting`) a higher or lower
/// voice at the same tempo.
public enum AudioVariations {
    public struct Variant: Sendable {
        public let name: String
        public let samples: [Float]
    }

    /// The original plus every variation of it.
    public static func variants(of samples: [Float], sampleRate: Double,
                                pitchShifter: PitchShifting?) -> [Variant] {
        var variants = [
            Variant(name: "original", samples: samples),
            Variant(name: "slower", samples: speed(samples, factor: 0.9)),
            Variant(name: "faster", samples: speed(samples, factor: 1.1)),
            Variant(name: "telephone", samples: bandLimit(samples, sampleRate: sampleRate, low: 300, high: 3400)),
            Variant(name: "noisy", samples: addNoise(samples, snrDB: 15, seed: 1)),
        ]
        if let pitchShifter {
            for (name, cents) in [("higher", 300), ("lower", -300)] {
                if let shifted = pitchShifter.shift(samples, sampleRate: sampleRate, cents: cents) {
                    variants.append(Variant(name: name, samples: shifted))
                }
            }
        }
        return variants
    }

    /// Plays the samples `factor` times as fast (tempo and pitch together), by linear
    /// interpolation. The result has `count / factor` samples.
    public static func speed(_ samples: [Float], factor: Double) -> [Float] {
        guard let last = samples.last, factor > 0 else { return [] }
        let count = Int(Double(samples.count) / factor)
        return (0..<count).map { i in
            let position = Double(i) * factor
            let index = Int(position)
            guard index + 1 < samples.count else { return last }
            let fraction = Float(position - Double(index))
            return samples[index] + (samples[index + 1] - samples[index]) * fraction
        }
    }

    /// Keeps roughly `low`–`high` Hz with a second-order high-pass then low-pass (RBJ
    /// biquads), like a phone line or a cheap headset mic.
    public static func bandLimit(_ samples: [Float], sampleRate: Double, low: Double, high: Double) -> [Float] {
        let highPassed = Biquad.highPass(cutoff: low, sampleRate: sampleRate).process(samples)
        return Biquad.lowPass(cutoff: high, sampleRate: sampleRate).process(highPassed)
    }

    /// Adds white noise `snrDB` below the signal's RMS level. Seeded, so the same input
    /// always gets the same noise.
    public static func addNoise(_ samples: [Float], snrDB: Double, seed: UInt64) -> [Float] {
        let signalPower = samples.reduce(0) { $0 + Double($1) * Double($1) } / Double(max(samples.count, 1))
        guard signalPower > 0 else { return samples }
        // Uniform noise in [-a, a] has RMS a/√3.
        let amplitude = sqrt(signalPower) / pow(10, snrDB / 20) * sqrt(3)
        var generator = SplitMix64(seed: seed)
        return samples.map { $0 + Float((generator.nextUnit() * 2 - 1) * amplitude) }
    }
}

/// A direct-form-I biquad filter.
private struct Biquad {
    let b0, b1, b2, a1, a2: Double

    static func lowPass(cutoff: Double, sampleRate: Double) -> Biquad {
        let (cosW, alpha) = terms(cutoff: cutoff, sampleRate: sampleRate)
        return normalized(b0: (1 - cosW) / 2, b1: 1 - cosW, b2: (1 - cosW) / 2,
                          a0: 1 + alpha, a1: -2 * cosW, a2: 1 - alpha)
    }

    static func highPass(cutoff: Double, sampleRate: Double) -> Biquad {
        let (cosW, alpha) = terms(cutoff: cutoff, sampleRate: sampleRate)
        return normalized(b0: (1 + cosW) / 2, b1: -(1 + cosW), b2: (1 + cosW) / 2,
                          a0: 1 + alpha, a1: -2 * cosW, a2: 1 - alpha)
    }

    /// alpha = sin(w) / 2Q with the Butterworth Q of 1/√2, so 2Q = √2.
    private static func terms(cutoff: Double, sampleRate: Double) -> (cosW: Double, alpha: Double) {
        let w = 2 * Double.pi * min(cutoff, sampleRate * 0.45) / sampleRate
        return (cos(w), sin(w) / 2.0.squareRoot())
    }

    private static func normalized(b0: Double, b1: Double, b2: Double,
                                   a0: Double, a1: Double, a2: Double) -> Biquad {
        Biquad(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    func process(_ samples: [Float]) -> [Float] {
        var (x1, x2, y1, y2) = (0.0, 0.0, 0.0, 0.0)
        return samples.map { sample in
            let x = Double(sample)
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            (x2, x1, y2, y1) = (x1, x, y1, y)
            return Float(y)
        }
    }
}

/// Small seeded generator, so variations are reproducible.
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// Uniform in [0, 1).
    mutating func nextUnit() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
