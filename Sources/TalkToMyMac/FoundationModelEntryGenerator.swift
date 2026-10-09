import FoundationModels
import TalkToMyMacCore

/// Fills in a dictionary entry from its written form using the on-device Foundation Model
/// with guided generation, so the result is always structurally valid. Returns nil when the
/// model is unavailable, refuses, errors, or times out — the user then fills fields by hand.
@available(macOS 26.0, *)
final class FoundationModelEntryGenerator: DictionaryEntryGenerating {
    private let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
    private let timeout: Duration

    init(timeout: Duration = .seconds(20)) {
        self.timeout = timeout
    }

    func suggestEntry(for written: String) async -> DictionaryEntry? {
        guard case .available = model.availability else {
            print("[FoundationModelEntryGenerator] Model unavailable: \(model.availability)")
            return nil
        }
        let session = LanguageModelSession(model: model, instructions: DictionaryEntryPrompt.instructions)
        let options = GenerationOptions(temperature: 0.2)

        return await withTaskGroup(of: DictionaryEntry?.self) { group in
            group.addTask {
                do {
                    let response = try await session.respond(
                        to: DictionaryEntryPrompt.prompt(for: written),
                        generating: GeneratedEntry.self,
                        options: options
                    )
                    return response.content.dictionaryEntry(written: written)
                } catch {
                    print("[FoundationModelEntryGenerator] respond failed: \(error)")
                    return nil
                }
            }
            group.addTask { [timeout] in
                try? await Task.sleep(for: timeout)
                return nil
            }
            defer { group.cancelAll() }
            return await group.next() ?? nil
        }
    }
}

@available(macOS 26.0, *)
@Generable
private struct GeneratedEntry {
    @Guide(description: "What kind of term this is")
    var type: GeneratedEntryType

    @Guide(description: "Ways a speech-to-text model might write the whole term when spoken; each covers the whole term",
           .count(2...4))
    var soundsLike: [String]

    @Guide(description: "Ordinary words that often appear in the same sentence as the term, never the term itself",
           .count(3...4))
    var neighborWords: [String]

    @Guide(description: "True only for code identifiers that belong in backticks")
    var formatAsCode: Bool

    @Guide(description: "False only for verbs that must never change form")
    var inflect: Bool

    func dictionaryEntry(written: String) -> DictionaryEntry {
        DictionaryEntryPrompt.entry(written: written, type: type.entryType, soundsLike: soundsLike,
                                    neighborWords: neighborWords, formatAsCode: formatAsCode, inflect: inflect)
    }
}

@available(macOS 26.0, *)
@Generable
private enum GeneratedEntryType {
    case noun, proper_noun, verb, adjective, identifier, acronym

    var entryType: DictionaryEntry.EntryType {
        switch self {
        case .noun:        return .noun
        case .proper_noun: return .properNoun
        case .verb:        return .verb
        case .adjective:   return .adjective
        case .identifier:  return .identifier
        case .acronym:     return .acronym
        }
    }
}
