import Foundation

/// Narrows the dictionary list to the words matching what the user typed in its filter field.
public enum DictionaryFilter {
    /// Items whose written form or a heard-as form fuzzy-matches `query`, best match first;
    /// ties keep dictionary order. An empty or whitespace-only query returns `items` as is.
    public static func filter(_ items: [DictionaryEditor.Item], query: String) -> [DictionaryEditor.Item] {
        guard !query.allSatisfy(\.isWhitespace) else { return items }
        return items.enumerated()
            .compactMap { offset, item in score(item.entry, query: query).map { (offset, item, $0) } }
            .sorted { $0.2 != $1.2 ? $0.2 > $1.2 : $0.0 < $1.0 }
            .map(\.1)
    }

    /// The entry's best score. Doubled so a written-form match wins a tie with an equally
    /// good heard-as match: typing the term itself should put it first.
    private static func score(_ entry: DictionaryEntry, query: String) -> Int? {
        let written = FuzzyMatch.score(query, in: entry.written).map { $0 * 2 + 1 }
        let heardAs = entry.soundsLike.compactMap { FuzzyMatch.score(query, in: $0) }.max().map { $0 * 2 }
        return [written, heardAs].compactMap { $0 }.max()
    }
}
