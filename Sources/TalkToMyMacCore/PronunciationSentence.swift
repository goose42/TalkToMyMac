import Foundation

/// The sentence the user says a dictionary term in while recording its pronunciation: the
/// default carrier, or a custom one they typed because the default doesn't fit.
public enum PronunciationSentence {
    public static func defaultSentence(for word: String) -> String {
        "\(PronunciationProbe.carrierPrefix) \(word) \(PronunciationProbe.carrierSuffix)"
    }

    /// The trimmed custom sentence, or `default` when it is nil, empty or only whitespace.
    public static func resolve(custom: String?, default fallback: String) -> String {
        let trimmed = custom?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    /// The words before and after the first occurrence of `word` (ignoring case), used to cut
    /// the term out of the transcript. Nil if the sentence doesn't contain the word.
    public static func carrier(in sentence: String, around word: String) -> (prefix: String, suffix: String)? {
        guard !word.isEmpty, let range = sentence.range(of: word, options: .caseInsensitive) else { return nil }
        let trim = CharacterSet.whitespacesAndNewlines
        return (sentence[..<range.lowerBound].trimmingCharacters(in: trim),
                sentence[range.upperBound...].trimmingCharacters(in: trim))
    }
}
