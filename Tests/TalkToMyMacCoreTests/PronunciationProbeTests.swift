import Synchronization
import XCTest
@testable import TalkToMyMacCore

/// Answers each `transcribeAlternatives` call with the next scripted list (empty once the
/// script runs out), recording what it was given.
final class ScriptedAlternativesTranscriber: SpeechTranscribing {
    var isReady = true
    var script: [[String]]
    private(set) var calls: [[Float]] = []

    init(_ script: [[String]]) {
        self.script = script
    }

    func transcribe(samples: [Float], sampleRate: Double) async -> TranscriptionOutcome? {
        await transcribeAlternatives(samples: samples, sampleRate: sampleRate).first
            .map { TranscriptionOutcome(text: $0, engine: .appleOnDevice) }
    }

    func transcribeAlternatives(samples: [Float], sampleRate: Double) async -> [String] {
        calls.append(samples)
        return script.isEmpty ? [] : script.removeFirst()
    }
}

final class PronunciationProbeTests: XCTestCase {

    private let take = PronunciationProbe.Take(samples: [0.1, 0.2], sampleRate: 16_000)
    /// Variants per take without a pitch shifter.
    private let perTake = 5

    // MARK: Slot extraction

    func testExtractSlotStripsCarrier() {
        XCTAssertEqual(PronunciationProbe.extractSlot(from: "I'm working with oh tell today."), "oh tell")
        XCTAssertEqual(PronunciationProbe.extractSlot(from: "i’m working with Hotel, today"), "Hotel")
        XCTAssertEqual(PronunciationProbe.extractSlot(from: "I am working with OTel today"), "OTel")
    }

    func testExtractSlotRejectsTranscriptsThatMissTheCarrier() {
        XCTAssertNil(PronunciationProbe.extractSlot(from: "I'm walking with hotel today"))
        XCTAssertNil(PronunciationProbe.extractSlot(from: "I'm working with hotel"))
        XCTAssertNil(PronunciationProbe.extractSlot(from: "I'm working with today"))
    }

    // MARK: Normalization

    func testNormalizeTrimsPunctuationAndSentenceCase() {
        XCTAssertEqual(PronunciationProbe.normalize("  Hotel. "), "hotel")
        XCTAssertEqual(PronunciationProbe.normalize("Oh tell?"), "oh tell")
        XCTAssertEqual(PronunciationProbe.normalize("OTel"), "OTel")
        XCTAssertEqual(PronunciationProbe.normalize("Open Tel"), "Open Tel")
        XCTAssertNil(PronunciationProbe.normalize(" ... "))
    }

    // MARK: Running

    func testRunTranscribesEveryVariantOfBothTakes() async {
        let transcriber = ScriptedAlternativesTranscriber([])
        let probe = PronunciationProbe(transcriber: transcriber, pitchShifter: nil)
        let progress = Mutex<[(Int, Int)]>([])
        _ = await probe.run(word: take, sentence: take, written: "OTel", existing: []) { done, total in
            progress.withLock { $0.append((done, total)) }
        }
        XCTAssertEqual(transcriber.calls.count, 2 * perTake)
        let reports = progress.withLock { $0 }
        XCTAssertEqual(reports.map(\.0), Array(1...(2 * perTake)))
        XCTAssertTrue(reports.allSatisfy { $0.1 == 2 * perTake })
    }

    func testRunFiltersWrittenExistingEmptyAndLongResults() async {
        let transcriber = ScriptedAlternativesTranscriber([
            ["Hotel.", "otel", "O tel", "", "one two three four five", "Oh tell"],
        ])
        let probe = PronunciationProbe(transcriber: transcriber, pitchShifter: nil)
        let result = await probe.run(word: take, sentence: nil, written: "OTel", existing: ["Oh Tell"])
        XCTAssertEqual(result.map(\.text), ["hotel", "o tel"])
    }

    func testRunCountsEachVariantOnceAndRanksByCount() async {
        let transcriber = ScriptedAlternativesTranscriber([
            ["hotel", "Hotel."],       // original: counted once
            ["oh tell"],
            ["oh tell", "hotel"],
            ["oh tell"],
            ["motel"],
        ])
        let probe = PronunciationProbe(transcriber: transcriber, pitchShifter: nil)
        let result = await probe.run(word: take, sentence: nil, written: "OTel", existing: [])
        XCTAssertEqual(result, [
            .init(text: "oh tell", count: 3),
            .init(text: "hotel", count: 2),
            .init(text: "motel", count: 1),
        ])
    }

    func testRunCapsCandidates() async {
        let transcriber = ScriptedAlternativesTranscriber([(1...12).map { "word\($0)" }])
        let probe = PronunciationProbe(transcriber: transcriber, pitchShifter: nil, maxCandidates: 3)
        let result = await probe.run(word: take, sentence: nil, written: "OTel", existing: [])
        XCTAssertEqual(result.map(\.text), ["word1", "word2", "word3"])
    }

    func testSentenceTakeContributesOnlyTheSlot() async {
        var script = Array(repeating: [String](), count: perTake)
        script.append(["I'm working with hotel today.", "I'm walking with motel today."])
        let transcriber = ScriptedAlternativesTranscriber(script)
        let probe = PronunciationProbe(transcriber: transcriber, pitchShifter: nil)
        let result = await probe.run(word: take, sentence: take, written: "OTel", existing: [])
        XCTAssertEqual(result.map(\.text), ["hotel"])
    }

    func testRunUsesPitchShifterVariants() async {
        let transcriber = ScriptedAlternativesTranscriber([])
        let probe = PronunciationProbe(transcriber: transcriber, pitchShifter: MockPitchShifter())
        _ = await probe.run(word: take, sentence: nil, written: "OTel", existing: [])
        XCTAssertEqual(transcriber.calls.count, perTake + 2)
    }

    func testDefaultTranscribeAlternativesWrapsTranscribe() async {
        let transcriber = MockTranscriber(result: "hotel")
        let alternatives = await transcriber.transcribeAlternatives(samples: [0], sampleRate: 16_000)
        XCTAssertEqual(alternatives, ["hotel"])
        let silent = MockTranscriber(result: nil)
        let none = await silent.transcribeAlternatives(samples: [0], sampleRate: 16_000)
        XCTAssertEqual(none, [])
    }
}
