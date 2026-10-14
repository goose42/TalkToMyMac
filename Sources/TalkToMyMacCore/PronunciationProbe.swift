import Foundation

/// Finds what the speech engine writes when it hears the user say a dictionary term. Each
/// recording is transcribed in several synthetic variations (`AudioVariations`), asking the
/// engine for its alternatives each time; whatever comes back that isn't the term itself is
/// a candidate "heard as" form, ranked by how many variations produced it.
public struct PronunciationProbe {
    public struct Take: Sendable {
        public let samples: [Float]
        public let sampleRate: Double

        public init(samples: [Float], sampleRate: Double) {
            self.samples = samples
            self.sampleRate = sampleRate
        }
    }

    public struct Candidate: Equatable, Sendable {
        public let text: String
        /// How many variations produced this form.
        public let count: Int

        public init(text: String, count: Int) {
            self.text = text
            self.count = count
        }
    }

    /// The sentence the user says the term in, around the blank. Engines transcribe a lone
    /// word differently from one in running speech, and knowing the surrounding words lets
    /// the term's part be cut out reliably.
    public static let carrierPrefix = "I'm working with"
    public static let carrierSuffix = "today"

    /// Longer results are the engine hearing something else entirely.
    static let maxWords = 4

    private let transcriber: SpeechTranscribing
    private let pitchShifter: PitchShifting?
    private let maxCandidates: Int

    public init(transcriber: SpeechTranscribing, pitchShifter: PitchShifting?, maxCandidates: Int = 8) {
        self.transcriber = transcriber
        self.pitchShifter = pitchShifter
        self.maxCandidates = maxCandidates
    }

    /// Transcribes every variation of both takes, one at a time, and returns the new forms:
    /// not `written` and not already in `existing` (ignoring case), most frequent first.
    /// `progress` gets (done, total) after each transcription.
    public func run(word: Take, sentence: Take?, written: String, existing: [String],
                    progress: (@Sendable (Int, Int) -> Void)? = nil) async -> [Candidate] {
        var jobs: [(samples: [Float], sampleRate: Double, isSentence: Bool)] = []
        for (take, isSentence) in [(word, false), (sentence, true)] {
            guard let take else { continue }
            for variant in AudioVariations.variants(of: take.samples, sampleRate: take.sampleRate,
                                                    pitchShifter: pitchShifter) {
                jobs.append((variant.samples, take.sampleRate, isSentence))
            }
        }

        let excluded = Set(([written] + existing).map { $0.lowercased() })
        var counts: [String: Int] = [:]
        var spelling: [String: String] = [:]
        var order: [String] = []

        for (done, job) in jobs.enumerated() {
            let alternatives = await transcriber.transcribeAlternatives(samples: job.samples,
                                                                        sampleRate: job.sampleRate)
            var seenInVariant = Set<String>()
            for alternative in alternatives {
                let raw = job.isSentence ? Self.extractSlot(from: alternative) : alternative
                guard let raw, let text = Self.normalize(raw),
                      text.split(separator: " ").count <= Self.maxWords else { continue }
                let key = text.lowercased()
                guard !excluded.contains(key), seenInVariant.insert(key).inserted else { continue }
                if counts[key] == nil {
                    order.append(key)
                    spelling[key] = text
                }
                counts[key, default: 0] += 1
            }
            progress?(done + 1, jobs.count)
        }

        // Stable sort: ties keep the order they were first heard in.
        let ranked = order.enumerated()
            .sorted { (counts[$0.element]!, -$0.offset) > (counts[$1.element]!, -$1.offset) }
            .map(\.element)
        return ranked.prefix(maxCandidates).map { Candidate(text: spelling[$0]!, count: counts[$0]!) }
    }

    /// The words between the carrier's prefix and suffix, or nil if the transcript doesn't
    /// follow the carrier (then it can't be told which words are the term).
    static func extractSlot(from transcript: String) -> String? {
        let words = transcript.split(whereSeparator: \.isWhitespace).map(String.init)
        let keys = words.map(comparisonKey)
        let suffix = carrierSuffix.split(separator: " ").map { comparisonKey(String($0)) }

        let prefixes = [carrierPrefix, "I am working with"].map {
            $0.split(separator: " ").map { comparisonKey(String($0)) }
        }
        guard let prefix = prefixes.first(where: { keys.starts(with: $0) }),
              keys.count > prefix.count + suffix.count,
              Array(keys.suffix(suffix.count)) == suffix else { return nil }

        let slot = words[prefix.count..<(words.count - suffix.count)].joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters)
        return slot.isEmpty ? nil : slot
    }

    /// Trims whitespace and surrounding punctuation, and undoes sentence capitalization: a
    /// form whose only capital is its first letter is lowercased ("Hotel." → "hotel"), while
    /// deliberate casing like "OTel" is kept. Nil if nothing is left.
    static func normalize(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard let first = trimmed.first else { return nil }
        let restHasCapitals = trimmed.dropFirst().contains { $0.isUppercase }
        return first.isUppercase && !restHasCapitals ? trimmed.lowercased() : trimmed
    }

    /// Lowercased with punctuation removed and curly apostrophes straightened, for matching
    /// carrier words.
    private static func comparisonKey(_ word: String) -> String {
        word.replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: .punctuationCharacters)
            .lowercased()
    }
}
