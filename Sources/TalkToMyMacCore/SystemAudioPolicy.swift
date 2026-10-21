/// What to do to the Mac's sound output while a recording is in progress.
public enum SystemAudioAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case mute
    /// Turn the volume down to a fraction of where it was, rather than silencing it.
    case dampen

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off:    return "Off"
        case .mute:   return "Mute"
        case .dampen: return "Dampen"
        }
    }
}

/// Which output devices the action applies to, by CoreAudio device UID. UIDs stay the same
/// when a device disconnects and comes back, unlike `AudioDeviceID`s.
public enum OutputDeviceScope: Equatable, Sendable {
    case all
    case only(Set<String>)
}

/// Decides what to do to the current output device while recording, so that e.g. speakers
/// are silenced (their sound leaks into the mic) while headphones are left alone.
public struct SystemAudioPolicy: Equatable, Sendable {
    public enum Plan: Equatable, Sendable {
        case leaveAlone
        case mute
        /// Set the volume to this fraction of its current value.
        case lower(toFraction: Double)
    }

    public static let defaultDampenLevel = 0.2

    public var action: SystemAudioAction
    /// Fraction of the current volume to lower to when dampening, in 0...1.
    public var dampenLevel: Double
    public var scope: OutputDeviceScope

    public init(action: SystemAudioAction, dampenLevel: Double = defaultDampenLevel, scope: OutputDeviceScope) {
        self.action = action
        self.dampenLevel = min(max(dampenLevel, 0), 1)
        self.scope = scope
    }

    public func plan(forDeviceUID uid: String) -> Plan {
        if case .only(let uids) = scope, !uids.contains(uid) { return .leaveAlone }
        switch action {
        case .off:    return .leaveAlone
        case .mute:   return .mute
        case .dampen: return .lower(toFraction: dampenLevel)
        }
    }

    /// The volume to set when dampening; never louder than `current`.
    public static func dampenedVolume(current: Float, level: Double) -> Float {
        current * Float(min(max(level, 0), 1))
    }
}
