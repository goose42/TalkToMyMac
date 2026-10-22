import Foundation

public enum WidgetMenuAction: Equatable, Sendable {
    case copyLastTranscript
    case toggleRecording
    case hideForAnHour
}

public struct WidgetMenuItem: Equatable, Sendable {
    public let action: WidgetMenuAction
    public let title: String
    /// SF Symbol name.
    public let symbol: String
    public let isEnabled: Bool
}

/// What the floating indicator's click menu offers right now.
public enum WidgetMenu {
    public static func items(isRecording: Bool, hasLastTranscript: Bool) -> [WidgetMenuItem] {
        [
            WidgetMenuItem(action: .copyLastTranscript, title: "Copy Last Dictation",
                           symbol: "doc.on.doc", isEnabled: hasLastTranscript),
            WidgetMenuItem(action: .toggleRecording,
                           title: isRecording ? "Stop Recording" : "Start Recording",
                           symbol: isRecording ? "stop.circle" : "record.circle", isEnabled: true),
            WidgetMenuItem(action: .hideForAnHour, title: "Hide for 1 Hour",
                           symbol: "eye.slash", isEnabled: true),
        ]
    }
}
