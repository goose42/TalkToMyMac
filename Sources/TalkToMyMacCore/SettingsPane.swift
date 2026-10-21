/// A section of the settings window, in sidebar order.
public enum SettingsPane: String, CaseIterable, Identifiable, Sendable {
    case general
    case audio
    case dictionary
    case formatting
    case models
    case transcriptions
    case instrumentation
    case storage

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general:         return "General"
        case .audio:           return "Audio"
        case .dictionary:      return "Dictionary"
        case .formatting:      return "Formatting"
        case .models:          return "Models"
        case .transcriptions:  return "Transcriptions"
        case .instrumentation: return "Instrumentation"
        case .storage:         return "Storage"
        }
    }

    /// SF Symbol name shown next to the title in the sidebar.
    public var symbol: String {
        switch self {
        case .general:         return "gearshape"
        case .audio:           return "speaker.wave.2"
        case .dictionary:      return "character.book.closed"
        case .formatting:      return "wand.and.stars"
        case .models:          return "cpu"
        case .transcriptions:  return "text.bubble"
        case .instrumentation: return "gauge.with.dots.needle.bottom.50percent"
        case .storage:         return "internaldrive"
        }
    }
}
