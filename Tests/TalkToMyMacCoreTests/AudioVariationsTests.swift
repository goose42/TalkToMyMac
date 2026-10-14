import XCTest
@testable import TalkToMyMacCore

/// Shifts every sample by a constant so tests can tell its output apart; returns nil for
/// downward shifts to exercise the "shifter couldn't render" path.
final class MockPitchShifter: PitchShifting {
    var requestedCents: [Int] = []

    func shift(_ samples: [Float], sampleRate: Double, cents: Int) -> [Float]? {
        requestedCents.append(cents)
        return samples.map { $0 + Float(cents) }
    }
}

final class AudioVariationsTests: XCTestCase {

    private let sampleRate = 16_000.0

    private func sine(_ frequency: Double, seconds: Double = 1) -> [Float] {
        (0..<Int(sampleRate * seconds)).map { Float(sin(2 * .pi * frequency * Double($0) / sampleRate)) }
    }

    private func rms(_ samples: [Float]) -> Float {
        sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(max(samples.count, 1)))
    }

    // MARK: Speed

    func testSpeedChangesLengthByInverseFactor() {
        let samples = sine(440)
        XCTAssertEqual(AudioVariations.speed(samples, factor: 0.9).count, Int(Double(samples.count) / 0.9))
        XCTAssertEqual(AudioVariations.speed(samples, factor: 1.1).count, Int(Double(samples.count) / 1.1))
    }

    func testSpeedInterpolatesBetweenSamples() {
        XCTAssertEqual(AudioVariations.speed([0, 1, 2, 3], factor: 0.5), [0, 0.5, 1, 1.5, 2, 2.5, 3, 3])
    }

    func testSpeedOfEmptyInputIsEmpty() {
        XCTAssertEqual(AudioVariations.speed([], factor: 1.1), [])
    }

    // MARK: Band limit

    func testBandLimitKeepsVoiceBandAndCutsBothEnds() {
        func gain(_ frequency: Double) -> Float {
            let input = sine(frequency)
            let output = AudioVariations.bandLimit(input, sampleRate: sampleRate, low: 300, high: 3400)
            // Skip the filter's start-up transient.
            return rms(Array(output.dropFirst(1600))) / rms(Array(input.dropFirst(1600)))
        }
        XCTAssertGreaterThan(gain(1000), 0.8)
        XCTAssertLessThan(gain(80), 0.5)
        XCTAssertLessThan(gain(7000), 0.5)
    }

    // MARK: Noise

    func testNoiseIsAddedAtRequestedSNR() {
        let input = sine(440)
        let output = AudioVariations.addNoise(input, snrDB: 20, seed: 1)
        let noise = zip(output, input).map { $0 - $1 }
        XCTAssertEqual(rms(input) / rms(noise), 10, accuracy: 0.5)
    }

    func testNoiseIsDeterministicPerSeed() {
        let input = sine(440)
        XCTAssertEqual(AudioVariations.addNoise(input, snrDB: 15, seed: 7),
                       AudioVariations.addNoise(input, snrDB: 15, seed: 7))
        XCTAssertNotEqual(AudioVariations.addNoise(input, snrDB: 15, seed: 7),
                          AudioVariations.addNoise(input, snrDB: 15, seed: 8))
    }

    func testNoiseLeavesSilenceAlone() {
        XCTAssertEqual(AudioVariations.addNoise([0, 0, 0], snrDB: 15, seed: 1), [0, 0, 0])
    }

    // MARK: Variants

    func testVariantsWithoutPitchShifter() {
        let input = sine(440)
        let variants = AudioVariations.variants(of: input, sampleRate: sampleRate, pitchShifter: nil)
        XCTAssertEqual(variants.map(\.name), ["original", "slower", "faster", "telephone", "noisy"])
        XCTAssertEqual(variants.first?.samples, input)
    }

    func testVariantsWithPitchShifterAddHigherAndLower() {
        let shifter = MockPitchShifter()
        let variants = AudioVariations.variants(of: [0, 0], sampleRate: sampleRate, pitchShifter: shifter)
        XCTAssertEqual(variants.map(\.name),
                       ["original", "slower", "faster", "telephone", "noisy", "higher", "lower"])
        XCTAssertEqual(shifter.requestedCents, [300, -300])
        XCTAssertEqual(variants.last?.samples, [-300, -300])
    }
}
