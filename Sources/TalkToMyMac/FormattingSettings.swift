import Foundation
import Observation
import TalkToMyMacCore

/// UserDefaults-backed, observable settings for the LLM formatting and auto-paste steps.
/// A single instance is shared between the formatters, `PasteDelivery`, and the
/// Settings UI so changes take effect immediately without restarting the app.
/// `@unchecked Sendable`: deliberately shared between the main-actor Settings UI and the
/// non-isolated formatter/paste-delivery objects on the recording pipeline. `@Observable`'s
/// change tracking is thread-agnostic by design, so reads/writes from either side are safe
/// in practice even though nothing here is actor-isolated.
@Observable
final class FormattingSettings: @unchecked Sendable {
    private enum Keys {
        static let llmFormattingEnabled = "llmFormattingEnabled"
        static let deterministicCleanupEnabled = "deterministicCleanupEnabled"
        static let promptPreset = "promptPreset"
        static let customInstructions = "customInstructions"
        static let autoPasteEnabled = "autoPasteEnabled"
        static let systemAudioAction = "systemAudioAction"
        static let systemAudioDampenLevel = "systemAudioDampenLevel"
        static let systemAudioAllDevices = "systemAudioAllDevices"
        static let systemAudioDeviceUIDs = "systemAudioDeviceUIDs"
        static let systemAudioDeviceNames = "systemAudioDeviceNames"
        static let inputDeviceUID = "inputDeviceUID"
        static let inputDeviceNames = "inputDeviceNames"
        static let builtInMicrophoneOnly = "builtInMicrophoneOnly"
        /// On/off toggle from before the Audio tab; migrated into `systemAudioAction` on launch.
        static let legacyMuteSystemAudioWhileRecording = "muteSystemAudioWhileRecording"
        static let skipShortDictations = "skipShortDictations"
        static let formattingWordThreshold = "formattingWordThreshold"
        static let dictionaryJSON = "dictionaryJSON"
        static let dictionaryFolderPath = "dictionaryFolderPath"
        static let formattingProvider = "formattingProvider"
        static let groqModel = "groqModel"
        static let openRouterModel = "openRouterModel"
        static let tokenPrices = "tokenPrices"
        static let formattingPause = "formattingPause"
        static let transcriptionEngine = "transcriptionEngine"
        static let parakeetLanguage = "parakeetLanguage"
        /// Plain word list from the first, unreleased version of the dictionary; migrated
        /// into `dictionaryJSON` on launch.
        static let legacyDictionaryWords = "dictionaryWords"
    }

    /// Whether the LLM formatting step runs at all. When false, `processRecording` delivers
    /// the transcript as is (after deterministic cleanup, if that's on).
    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.llmFormattingEnabled) }
    }

    /// Whether the model-free cleanup step (fillers, repairs, voice commands, numbers, email
    /// layout) runs before formatting. Dictionary fixes run regardless. Independent of
    /// `isEnabled`: with the LLM off, its output is what gets delivered.
    var deterministicCleanupEnabled: Bool {
        didSet { UserDefaults.standard.set(deterministicCleanupEnabled, forKey: Keys.deterministicCleanupEnabled) }
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

    /// Which model formats transcripts: Apple's on-device model or a remote one.
    var provider: FormattingProvider {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: Keys.formattingProvider) }
    }

    /// Which speech-to-text model transcribes dictations. An external model is only used once
    /// it's loaded; until then — and after it's unloaded — Apple's on-device model is.
    var transcriptionEngine: TranscriptionEngine {
        didSet { UserDefaults.standard.set(transcriptionEngine.rawValue, forKey: Keys.transcriptionEngine) }
    }

    /// The language Parakeet should expect, or nil to let it detect the language (the default).
    var parakeetLanguage: ParakeetLanguage? {
        didSet { UserDefaults.standard.set(parakeetLanguage?.rawValue, forKey: Keys.parakeetLanguage) }
    }

    /// The model used when `provider` is `.groq`.
    var groqModel: GroqModel {
        didSet { UserDefaults.standard.set(groqModel.rawValue, forKey: Keys.groqModel) }
    }

    /// The model used when `provider` is `.openRouter`.
    var openRouterModel: OpenRouterModel {
        didSet { UserDefaults.standard.set(openRouterModel.rawValue, forKey: Keys.openRouterModel) }
    }

    /// Set after a remote formatting call fails, switching that provider off for an hour.
    /// Stays set after it expires until the next pause or `resumeFormatting()`; check
    /// `activePause` for whether it still applies.
    private(set) var formattingPause: FormattingPause? {
        didSet {
            UserDefaults.standard.set(formattingPause.flatMap { try? JSONEncoder().encode($0) },
                                      forKey: Keys.formattingPause)
        }
    }

    /// The pause on the selected provider, if it hasn't expired.
    var activePause: FormattingPause? {
        formattingPause.flatMap { $0.isActive(for: provider) ? $0 : nil }
    }

    func pauseFormatting(_ pause: FormattingPause) {
        formattingPause = pause
    }

    /// Ends a pause early, so the next dictation is formatted again.
    func resumeFormatting() {
        formattingPause = nil
    }

    /// Prices the user set for remote models, keyed by model ID. Models without an entry use
    /// their provider's list price; see `price(for:)`.
    private(set) var tokenPrices: [String: TokenPrice] {
        didSet {
            UserDefaults.standard.set(try? JSONEncoder().encode(tokenPrices), forKey: Keys.tokenPrices)
        }
    }

    /// Whether a successful transcript should be pasted at the cursor automatically.
    var autoPasteEnabled: Bool {
        didSet { UserDefaults.standard.set(autoPasteEnabled, forKey: Keys.autoPasteEnabled) }
    }

    /// What happens to the Mac's sound output for the length of each recording.
    var systemAudioAction: SystemAudioAction {
        didSet { UserDefaults.standard.set(systemAudioAction.rawValue, forKey: Keys.systemAudioAction) }
    }

    /// Fraction of the current volume to lower to when `systemAudioAction` is `.dampen`.
    var systemAudioDampenLevel: Double {
        didSet { UserDefaults.standard.set(systemAudioDampenLevel, forKey: Keys.systemAudioDampenLevel) }
    }

    /// Whether `systemAudioAction` applies whatever the output device is, or only when it's
    /// one of `systemAudioDeviceUIDs`.
    var systemAudioAllDevices: Bool {
        didSet { UserDefaults.standard.set(systemAudioAllDevices, forKey: Keys.systemAudioAllDevices) }
    }

    /// CoreAudio UIDs of the output devices `systemAudioAction` applies to when
    /// `systemAudioAllDevices` is off.
    var systemAudioDeviceUIDs: Set<String> {
        didSet { UserDefaults.standard.set(systemAudioDeviceUIDs.sorted(), forKey: Keys.systemAudioDeviceUIDs) }
    }

    /// Last-seen names of output devices by UID, so selected devices that aren't connected
    /// right now (headphones in a drawer) still show by name in Settings.
    var systemAudioDeviceNames: [String: String] {
        didSet { UserDefaults.standard.set(systemAudioDeviceNames, forKey: Keys.systemAudioDeviceNames) }
    }

    /// Which microphone recordings come from.
    var inputDevice: InputDeviceSelection {
        didSet { UserDefaults.standard.set(inputDevice.persistedUID, forKey: Keys.inputDeviceUID) }
    }

    /// Records only from the Mac's built-in microphone and switches off everything that watches
    /// or touches other audio devices (device-change listener, device list reads, muting the
    /// output). For when a Bluetooth headset makes dictation laggy or drops words.
    var builtInMicrophoneOnly: Bool {
        didSet {
            UserDefaults.standard.set(builtInMicrophoneOnly, forKey: Keys.builtInMicrophoneOnly)
            onBuiltInMicrophoneOnlyChange?()
        }
    }

    /// Called after `builtInMicrophoneOnly` changes, so the audio stack can start or stop watching.
    @ObservationIgnored var onBuiltInMicrophoneOnlyChange: (() -> Void)?

    /// Last-seen names of input devices by UID, so a chosen microphone that isn't connected
    /// right now still shows by name in Settings.
    var inputDeviceNames: [String: String] {
        didSet { UserDefaults.standard.set(inputDeviceNames, forKey: Keys.inputDeviceNames) }
    }

    var systemAudioPolicy: SystemAudioPolicy {
        SystemAudioPolicy(action: systemAudioAction, dampenLevel: systemAudioDampenLevel,
                          scope: systemAudioAllDevices ? .all : .only(systemAudioDeviceUIDs))
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
        deterministicCleanupEnabled = defaults.object(forKey: Keys.deterministicCleanupEnabled) as? Bool ?? false
        autoPasteEnabled = defaults.object(forKey: Keys.autoPasteEnabled) as? Bool ?? true
        if let raw = defaults.string(forKey: Keys.systemAudioAction), let saved = SystemAudioAction(rawValue: raw) {
            systemAudioAction = saved
        } else {
            let legacyMute = defaults.object(forKey: Keys.legacyMuteSystemAudioWhileRecording) as? Bool ?? false
            systemAudioAction = legacyMute ? .mute : .off
        }
        systemAudioDampenLevel = defaults.object(forKey: Keys.systemAudioDampenLevel) as? Double
            ?? SystemAudioPolicy.defaultDampenLevel
        systemAudioAllDevices = defaults.object(forKey: Keys.systemAudioAllDevices) as? Bool ?? true
        systemAudioDeviceUIDs = Set(defaults.stringArray(forKey: Keys.systemAudioDeviceUIDs) ?? [])
        systemAudioDeviceNames = defaults.dictionary(forKey: Keys.systemAudioDeviceNames) as? [String: String] ?? [:]
        inputDevice = InputDeviceSelection(persistedUID: defaults.string(forKey: Keys.inputDeviceUID))
        inputDeviceNames = defaults.dictionary(forKey: Keys.inputDeviceNames) as? [String: String] ?? [:]
        builtInMicrophoneOnly = defaults.bool(forKey: Keys.builtInMicrophoneOnly)
        skipShortDictations = defaults.object(forKey: Keys.skipShortDictations) as? Bool ?? false
        formattingWordThreshold = defaults.object(forKey: Keys.formattingWordThreshold) as? Int ?? 3
        provider = defaults.string(forKey: Keys.formattingProvider).flatMap(FormattingProvider.init) ?? .default
        groqModel = defaults.string(forKey: Keys.groqModel).flatMap(GroqModel.init) ?? .default
        openRouterModel = defaults.string(forKey: Keys.openRouterModel).flatMap(OpenRouterModel.init) ?? .default
        transcriptionEngine = defaults.string(forKey: Keys.transcriptionEngine)
            .flatMap(TranscriptionEngine.init(rawValue:)) ?? .default
        parakeetLanguage = ParakeetLanguage(persisted: defaults.string(forKey: Keys.parakeetLanguage))
        formattingPause = defaults.data(forKey: Keys.formattingPause)
            .flatMap { try? JSONDecoder().decode(FormattingPause.self, from: $0) }
        tokenPrices = defaults.data(forKey: Keys.tokenPrices)
            .flatMap { try? JSONDecoder().decode([String: TokenPrice].self, from: $0) } ?? [:]
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
    /// than sending an empty instructions string.
    var resolvedInstructions: String {
        customInstructions.isEmpty ? (PromptPreset.default.instructions ?? "") : customInstructions
    }

    // MARK: Token prices

    /// What `model` costs per token: the user's price if they set one, else the provider's
    /// list price. Nil for on-device models and remote models with no known price.
    func price(for model: FormattingModel) -> TokenPrice? {
        tokenPrices[model.modelID] ?? listPrice(for: model)
    }

    /// The provider's published price for `model`. Nil for on-device models and remote
    /// models with no known price.
    func listPrice(for model: FormattingModel) -> TokenPrice? {
        switch model.provider {
        case .appleOnDevice: return nil
        case .groq:          return GroqModel(rawValue: model.modelID)?.listPrice
        case .openRouter:    return OpenRouterModel(rawValue: model.modelID)?.listPrice
        }
    }

    func setPrice(_ price: TokenPrice, for model: FormattingModel) {
        tokenPrices[model.modelID] = price
    }

    /// Drops the user's price for `model`, going back to the list price.
    func resetPrice(for model: FormattingModel) {
        tokenPrices[model.modelID] = nil
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
