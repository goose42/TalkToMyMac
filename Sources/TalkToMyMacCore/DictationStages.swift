/// What each step of the pipeline did to one recorded dictation: speech-to-text produced the
/// raw text, deterministic cleanup may have changed it, then the LLM may have formatted it.
/// Any part of a record can be missing — tables are purged independently, and older versions
/// didn't record the cleaned text — so each stage says when it can't tell.
public struct DictationStages: Equatable, Sendable {
    /// What the store holds for the cleanup step.
    public enum CleanupRecord: Equatable, Sendable {
        /// Recorded before cleanup was stored, or purged.
        case notRecorded
        /// The cleaned text, or nil if cleanup didn't run.
        case recorded(String?)
    }

    /// Whether formatting was attempted and whether its output was delivered.
    public struct FormattingRecord: Equatable, Sendable {
        public let attempted: Bool
        public let applied: Bool

        public init(attempted: Bool, applied: Bool) {
            self.attempted = attempted
            self.applied = applied
        }
    }

    public enum Cleanup: Equatable, Sendable {
        case notRecorded
        /// Cleanup was off, or the dictation wasn't in English.
        case off
        /// Words changed from the raw text; nil if the raw text is gone.
        case applied(changedWords: Int?)
    }

    public enum Formatting: Equatable, Sendable {
        case notRecorded
        /// Formatting was off, or the dictation was too short to format.
        case skipped
        /// The model failed or timed out, so the unformatted text was delivered.
        case failed
        /// Words changed from the formatter's input; nil if that input is gone.
        case applied(changedWords: Int?)
    }

    public let cleanup: Cleanup
    public let formatting: Formatting

    /// `formatting` is nil when the dictation's metrics aren't recorded.
    public init(raw: String?, cleanup record: CleanupRecord, final: String, formatting: FormattingRecord?) {
        let cleaned: String?
        switch record {
        case .notRecorded:
            cleanup = .notRecorded
            cleaned = nil
        case .recorded(nil):
            cleanup = .off
            cleaned = nil
        case .recorded(let text?):
            cleanup = .applied(changedWords: raw.map { WordDiff.changedWords(from: $0, to: text) })
            cleaned = text
        }

        switch formatting {
        case nil:
            self.formatting = .notRecorded
        case let record? where record.applied:
            let input = Self.formatterInput(raw: raw, cleaned: cleaned)
            self.formatting = .applied(changedWords: input.map { WordDiff.changedWords(from: $0, to: final) })
        case let record? where record.attempted:
            self.formatting = .failed
        case _?:
            self.formatting = .skipped
        }
    }

    /// What the formatter was given: the cleaned text when cleanup ran, else the raw text.
    public static func formatterInput(raw: String?, cleaned: String?) -> String? {
        cleaned ?? raw
    }
}
