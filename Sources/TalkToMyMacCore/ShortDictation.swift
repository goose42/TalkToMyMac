/// Dictations this short read as fragments ("sounds good"), not sentences, so they lose the
/// trailing period and the sentence-start capital.
public enum ShortDictation {
    public static let maxWords = 2

    /// Drops one trailing period (not an ellipsis) and lowercases the first letter when the
    /// first word is plainly capitalized — "I", "OK" and "iPhone" keep their case.
    public static func apply(_ text: String) -> String {
        guard WordDiff.wordCount(text) <= maxWords else { return text }
        var result = text
        if result.hasSuffix("."), !result.hasSuffix("..") { result.removeLast() }
        let firstWord = result.prefix { $0.isLetter }
        if let first = firstWord.first, first.isUppercase, firstWord.count > 1,
           firstWord.dropFirst().allSatisfy(\.isLowercase) {
            result = first.lowercased() + result.dropFirst()
        }
        return result
    }
}
