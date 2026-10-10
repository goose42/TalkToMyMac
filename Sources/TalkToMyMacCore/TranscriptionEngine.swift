import Foundation

/// Which speech-to-text model transcribes dictations.
public enum TranscriptionEngine: String, CaseIterable, Hashable, Sendable {
    /// Apple's `SpeechAnalyzer`, managed by macOS. Always available as the fallback.
    case appleOnDevice
    /// NVIDIA Parakeet TDT 0.6B v3 as a Core ML model, run on-device through FluidAudio.
    case parakeetTDTv3

    /// The engine selected on first launch.
    public static let `default`: TranscriptionEngine = .appleOnDevice

    /// Looks an engine up by its `modelID`, e.g. when reading the metrics table.
    public init?(modelID: String) {
        guard let engine = Self.allCases.first(where: { $0.modelID == modelID }) else { return nil }
        self = engine
    }

    /// Stable identifier recorded with each dictation.
    public var modelID: String {
        switch self {
        case .appleOnDevice: return "apple-on-device"
        case .parakeetTDTv3: return "parakeet-tdt-0.6b-v3"
        }
    }

    public var displayName: String {
        switch self {
        case .appleOnDevice: return "Apple Speech (on-device)"
        case .parakeetTDTv3: return "Parakeet TDT 0.6B v3"
        }
    }

    /// Whether the app downloads and hosts this model itself, rather than macOS.
    public var isExternal: Bool { self != .appleOnDevice }

    /// The engine that should actually transcribe: the selected one once its model is loaded,
    /// otherwise Apple's — so dictation keeps working while a model downloads or loads, and
    /// unloading a model drops straight back to Apple's.
    public static func resolve(selected: TranscriptionEngine, externalState: ExternalModelState) -> TranscriptionEngine {
        guard selected.isExternal, externalState == .ready else { return .appleOnDevice }
        return selected
    }
}

/// Lifecycle of a model the app downloads and hosts itself.
public enum ExternalModelState: Equatable, Sendable {
    case notDownloaded
    case downloading
    /// On disk, but not loaded into memory.
    case downloaded
    case loading
    /// Loaded and able to transcribe.
    case ready
    case failed(String)

    /// Whether the model's files are on disk.
    public var isOnDisk: Bool {
        switch self {
        case .downloaded, .loading, .ready:          return true
        case .notDownloaded, .downloading, .failed:  return false
        }
    }
}

/// What one transcription produced, and which engine produced it.
public struct TranscriptionOutcome: Equatable, Sendable {
    public let text: String
    public let engine: TranscriptionEngine

    public init(text: String, engine: TranscriptionEngine) {
        self.text = text
        self.engine = engine
    }
}
