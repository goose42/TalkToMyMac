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
        static let minimumFormattingSeconds = "minimumFormattingSeconds"
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

    /// When true, recordings shorter than `minimumFormattingSeconds` skip the LLM step and
    /// deliver the raw transcript — a word or two (often a correction) isn't worth formatting.
    var skipShortDictations: Bool {
        didSet { UserDefaults.standard.set(skipShortDictations, forKey: Keys.skipShortDictations) }
    }

    /// Recording length, in seconds, below which formatting is skipped when
    /// `skipShortDictations` is on.
    var minimumFormattingSeconds: Double {
        didSet { UserDefaults.standard.set(minimumFormattingSeconds, forKey: Keys.minimumFormattingSeconds) }
    }

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
            resolvedPreset = .cleanUp
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
        minimumFormattingSeconds = defaults.object(forKey: Keys.minimumFormattingSeconds) as? Double ?? 2.0
        preset = resolvedPreset
        customInstructions = resolvedCustomInstructions
    }

    /// The system prompt actually sent to the model. Falls back to the Clean Up preset if
    /// the editor is somehow empty (e.g. `.custom` selected with nothing typed yet), rather
    /// than sending an empty instructions string.
    var resolvedInstructions: String {
        customInstructions.isEmpty ? (PromptPreset.cleanUp.instructions ?? "") : customInstructions
    }

    /// Restores the text editor to the selected preset's built-in text.
    func resetCustomInstructionsToCurrentPreset() {
        customInstructions = preset.instructions ?? ""
    }
}
