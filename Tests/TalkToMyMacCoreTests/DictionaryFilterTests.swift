import XCTest
@testable import TalkToMyMacCore

@MainActor
final class DictionaryFilterTests: XCTestCase {

    private func items(_ entries: [DictionaryEntry]) -> [DictionaryEditor.Item] {
        DictionaryEditor(entries: entries, generator: nil) { _ in }.items
    }

    private func filtered(_ entries: [DictionaryEntry], _ query: String) -> [String] {
        DictionaryFilter.filter(items(entries), query: query).map(\.entry.written)
    }

    private let otel = DictionaryEntry(written: "OTel", type: .acronym, soundsLike: ["hotel", "oh tel"])
    private let kubernetes = DictionaryEntry(written: "Kubernetes", type: .properNoun, soundsLike: ["cooper nettys"])
    private let kubectl = DictionaryEntry(written: "kubectl", type: .identifier)

    func testEmptyQueryReturnsEveryItemInDictionaryOrder() {
        let all = items([otel, kubernetes, kubectl])
        XCTAssertEqual(DictionaryFilter.filter(all, query: ""), all)
        XCTAssertEqual(DictionaryFilter.filter(all, query: "  "), all)
    }

    func testDropsItemsThatDontMatch() {
        XCTAssertEqual(filtered([otel, kubernetes, kubectl], "kub"), ["Kubernetes", "kubectl"])
        XCTAssertEqual(filtered([otel, kubernetes, kubectl], "zzz"), [])
    }

    func testMatchesHeardAsForms() {
        XCTAssertEqual(filtered([otel, kubernetes, kubectl], "hotel"), ["OTel"])
        XCTAssertEqual(filtered([otel, kubernetes, kubectl], "cooper"), ["Kubernetes"])
    }

    func testWrittenMatchOutranksEqualHeardAsMatch() {
        let heardAsRest = DictionaryEntry(written: "REST", type: .acronym, soundsLike: ["rust"])
        let rust = DictionaryEntry(written: "Rust", type: .properNoun)
        XCTAssertEqual(filtered([heardAsRest, rust], "rust"), ["Rust", "REST"])
    }

    func testBestMatchFirst() {
        let entries = [
            DictionaryEntry(written: "upgrade", type: .verb),
            DictionaryEntry(written: "PostGres", type: .properNoun),
            DictionaryEntry(written: "pg", type: .identifier),
        ]
        XCTAssertEqual(filtered(entries, "pg"), ["pg", "PostGres", "upgrade"])
    }

    func testTiesKeepDictionaryOrder() {
        let entries = [
            DictionaryEntry(written: "tel b", type: .noun),
            DictionaryEntry(written: "tel a", type: .noun),
            DictionaryEntry(written: "tel c", type: .noun),
        ]
        XCTAssertEqual(filtered(entries, "tel"), ["tel b", "tel a", "tel c"])
    }
}
