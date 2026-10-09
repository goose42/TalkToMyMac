import Foundation
import Observation
import TalkToMyMacCore

/// UserDefaults-backed, observable settings for the LLM formatting and auto-paste steps.
/// A single instance is shared between `FoundationModelFormatter`, `PasteDelivery`, and the
/// Settings UI so changes take effect immediately without restarting the app.
/// `@unchecked Sendable`: deliberately shared between the main-actor Settings UI and the
/// non-isolated formatter/paste-delivery objects on the recording pipeline. `@Observable`'s
/// change tracking is thread-agnostic by design, so reads/writes from either side are safe
/// in practice even though nothing here is actor-isolated.
@Observable
final class FormattingSettings: @unchecked Sendable {
    private enum Keys {
        static let llmFormattingEnabled = "llmFormattingEnabled"
        static let promptPreset = "promptPreset"
        static let customInstructions = "customInstructions"
        static let autoPasteEnabled = "autoPasteEnabled"
        static let skipShortDictations = "skipShortDictations"
        static let formattingWordThreshold = "formattingWordThreshold"
        static let dictionaryJSON = "dictionaryJSON"
        static let dictionaryFolderPath = "dictionaryFolderPath"
        /// Plain word list from the first, unreleased version of the dictionary; migrated
        /// into `dictionaryJSON` on launch.
        static let legacyDictionaryWords = "dictionaryWords"
    }

    /// Whether the LLM formatting step runs at all. When false, `processRecording` delivers
    /// the raw transcript untouched.
    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.llmFormattingEnabled) }
    }

    /// Which preset is selected in Settings. Changing this repopulates `customInstructions`
    /// with that preset's built-in text (or clears it, for `.custom`).
    var preset: PromptPreset {
        didSet {
            UserDefaults.standard.set(preset.rawValue, forKey: Keys.promptPreset)
            customInstructions = preset.instructions ?? ""
        }
    }

    /// The live contents of the Settings text editor — this, not the preset, is what actually
    /// gets sent as the system prompt. Selecting a preset just seeds this field.
    var customInstructions: String {
        didSet { UserDefaults.standard.set(customInstructions, forKey: Keys.customInstructions) }
    }

    /// When true, transcripts of `formattingWordThreshold` words or fewer skip the LLM step
    /// and are delivered raw — a word or two (often a correction) isn't worth formatting.
    var skipShortDictations: Bool {
        didSet { UserDefaults.standard.set(skipShortDictations, forKey: Keys.skipShortDictations) }
    }

    /// Transcripts must have more than this many words to be formatted when
    /// `skipShortDictations` is on.
    var formattingWordThreshold: Int {
        didSet { UserDefaults.standard.set(formattingWordThreshold, forKey: Keys.formattingWordThreshold) }
    }

    /// The custom dictionary: terms the speech model tends to mis-hear. Persisted as a JSON
    /// array (the same shape the formatting prompt receives) in UserDefaults and, when a
    /// folder is chosen, in its `dictionary.json`.
    var dictionaryEntries: [DictionaryEntry] {
        didSet { persistDictionary() }
    }

    /// Where `dictionary.json` lives, e.g. a folder in iCloud Drive. When set, the file is the
    /// source of truth: it's read at launch and rewritten on every change, and UserDefaults
    /// only keeps a fallback copy. Nil keeps the dictionary in UserDefaults alone.
    private(set) var dictionaryFolder: URL?

    /// Why the folder's `dictionary.json` can't be used. While set, the file is left alone so
    /// a hand edit or another Mac's copy isn't clobbered; `overwriteDictionaryFile()` resolves it.
    private(set) var dictionaryFileError: String?

    /// Whether a successful transcript should be pasted at the cursor automatically.
    var autoPasteEnabled: Bool {
        didSet { UserDefaults.standard.set(autoPasteEnabled, forKey: Keys.autoPasteEnabled) }
    }

    init() {
        // Resolve everything into locals first: the @Observable macro backs each stored
        // property with an accessor that requires `self` to be fully initialized before
        // it can be called, so `self.preset` can't be read here until every property
        // (including `customInstructions`) already has a value assigned.
        let defaults = UserDefaults.standard

        let resolvedPreset: PromptPreset
        if let raw = defaults.string(forKey: Keys.promptPreset), let saved = PromptPreset(rawValue: raw) {
            resolvedPreset = saved
        } else {
            resolvedPreset = .default
        }

        let resolvedCustomInstructions: String
        if let saved = defaults.string(forKey: Keys.customInstructions), !saved.isEmpty {
            resolvedCustomInstructions = saved
        } else {
            resolvedCustomInstructions = resolvedPreset.instructions ?? ""
        }

        isEnabled = defaults.object(forKey: Keys.llmFormattingEnabled) as? Bool ?? true
        autoPasteEnabled = defaults.object(forKey: Keys.autoPasteEnabled) as? Bool ?? true
        skipShortDictations = defaults.object(forKey: Keys.skipShortDictations) as? Bool ?? false
        formattingWordThreshold = defaults.object(forKey: Keys.formattingWordThreshold) as? Int ?? 3
        if let saved = defaults.string(forKey: Keys.dictionaryJSON) {
            do {
                dictionaryEntries = try DictionaryEntry.parse(saved)
            } catch {
                print("[FormattingSettings] Ignoring unreadable dictionary: \(error)")
                dictionaryEntries = []
            }
        } else if let words = defaults.stringArray(forKey: Keys.legacyDictionaryWords) {
            // `didSet` doesn't run during init, so persist the migrated entries explicitly.
            let migrated = words.map { DictionaryEntry(written: $0, type: .noun) }
            defaults.set(DictionaryEntry.encode(migrated), forKey: Keys.dictionaryJSON)
            defaults.removeObject(forKey: Keys.legacyDictionaryWords)
            dictionaryEntries = migrated
        } else {
            dictionaryEntries = []
        }
        dictionaryFolder = defaults.string(forKey: Keys.dictionaryFolderPath).map { URL(fileURLWithPath: $0) }
        preset = resolvedPreset
        customInstructions = resolvedCustomInstructions
        reloadDictionaryFile()
    }

    /// The system prompt actually sent to the model. Falls back to the default preset if
    /// the editor is somehow empty (e.g. `.custom` selected with nothing typed yet), rather
    /// than sending an empty instructions string. The custom dictionary is inserted at the
    /// prompt's `{{DICTIONARY}}` placeholder, or appended if it has none.
    var resolvedInstructions: String {
        FormattingInstructions.compose(base: baseInstructions, dictionary: dictionaryEntries)
    }

    /// Whether the active instructions place the dictionary themselves (and so carry the
    /// full dictionary rules), rather than getting the short appended version.
    var resolvedInstructionsHavePlaceholder: Bool {
        baseInstructions.contains(FormattingInstructions.dictionaryPlaceholder)
    }

    private var baseInstructions: String {
        customInstructions.isEmpty ? (PromptPreset.default.instructions ?? "") : customInstructions
    }

    /// Restores the text editor to the selected preset's built-in text.
    func resetCustomInstructionsToCurrentPreset() {
        customInstructions = preset.instructions ?? ""
    }

    // MARK: Dictionary file

    /// Re-reads the folder's `dictionary.json`, which wins over the current entries; a missing
    /// file is created from them. Returns the file's entries if they replaced the current ones.
    @discardableResult
    func reloadDictionaryFile() -> [DictionaryEntry]? {
        guard case .loaded(let entries) = readDictionaryFile(), entries != dictionaryEntries else { return nil }
        dictionaryEntries = entries
        // `didSet` doesn't run when this is called from `init`.
        persistDictionary()
        return entries
    }

    /// Moves the dictionary to `folder`, or back to UserDefaults alone if nil. A dictionary
    /// already in the folder is merged in: current entries first, then its new words.
    /// Returns the resulting entries.
    func useDictionaryFolder(_ folder: URL?) -> [DictionaryEntry] {
        dictionaryFolder = folder
        UserDefaults.standard.set(folder?.path, forKey: Keys.dictionaryFolderPath)
        if case .loaded(let fileEntries) = readDictionaryFile() {
            dictionaryEntries = DictionaryFile.merge(current: dictionaryEntries, file: fileEntries)
        }
        persistDictionary()
        return dictionaryEntries
    }

    /// Replaces an unreadable `dictionary.json` with the current entries.
    func overwriteDictionaryFile() {
        dictionaryFileError = nil
        persistDictionary()
    }

    private enum FileState {
        case none
        case loaded([DictionaryEntry])
        case unusable
    }

    /// Reads the folder's file and updates `dictionaryFileError`. A missing file (and not
    /// one iCloud has yet to download) is written from the current entries.
    private func readDictionaryFile() -> FileState {
        guard let folder = dictionaryFolder else {
            dictionaryFileError = nil
            return .none
        }
        let url = DictionaryFile.url(in: folder)
        do {
            if let entries = try DictionaryFile.load(from: url) {
                dictionaryFileError = nil
                return .loaded(entries)
            }
        } catch {
            dictionaryFileError = "dictionary.json can't be read: \(error). "
                + "Fix the file, or overwrite it with the words below."
            return .unusable
        }
        if DictionaryFile.isAwaitingICloudDownload(in: folder) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            dictionaryFileError = "dictionary.json is still downloading from iCloud. "
                + "Reopen Settings once it's done, or overwrite it with the words below."
            return .unusable
        }
        dictionaryFileError = nil
        persistDictionary()
        return .none
    }

    private func persistDictionary() {
        let json = DictionaryEntry.encode(dictionaryEntries)
        UserDefaults.standard.set(json, forKey: Keys.dictionaryJSON)
        guard let folder = dictionaryFolder, dictionaryFileError == nil else { return }
        do {
            try DictionaryFile.save(dictionaryEntries, to: DictionaryFile.url(in: folder))
        } catch {
            dictionaryFileError = "Couldn't save dictionary.json: \(error.localizedDescription)"
        }
    }
}
