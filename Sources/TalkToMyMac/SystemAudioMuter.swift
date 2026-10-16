import CoreAudio
import OSLog
import TalkToMyMacCore

/// Mutes the default output device while a recording is in progress, when
/// `settings.muteSystemAudioWhileRecording` is on. The setting is read at the start of each
/// recording, so toggling it in Settings takes effect on the next dictation.
///
/// Restores exactly what it changed, on the device it changed: a Mac that was already muted
/// stays muted, and switching output devices mid-recording doesn't leave the old one silent.
/// Devices without a mute control (some HDMI/USB outputs) are turned down to zero volume
/// instead, and turned back up afterwards.
///
/// `@unchecked Sendable`: held by the non-isolated `RecorderController`, which calls it
/// synchronously from the main thread when recordings start and stop; the pending-restore
/// state is only touched from there.
final class SystemAudioMuter: SystemAudioMuting, @unchecked Sendable {
    /// What `muteForRecording()` changed and must undo.
    private enum Change {
        case muted(AudioDeviceID)
        case volume(AudioDeviceID, previous: Float32)
    }

    private let settings: FormattingSettings
    private var pending: Change?
    private let logger = Logger(subsystem: "com.talktomymac.dictate", category: "SystemAudioMuter")

    init(settings: FormattingSettings) {
        self.settings = settings
    }

    func muteForRecording() {
        guard settings.muteSystemAudioWhileRecording, pending == nil,
              let device = Self.defaultOutputDevice() else { return }

        if Self.isSettable(device, Self.muteAddress) {
            // Already muted by the user: nothing to do, and nothing to undo.
            guard Self.read(UInt32.self, device, Self.muteAddress) == 0 else { return }
            if Self.write(UInt32(1), device, Self.muteAddress) {
                pending = .muted(device)
            }
        } else if Self.isSettable(device, Self.volumeAddress),
                  let volume = Self.read(Float32.self, device, Self.volumeAddress), volume > 0 {
            if Self.write(Float32(0), device, Self.volumeAddress) {
                pending = .volume(device, previous: volume)
            }
        } else {
            logger.notice("Default output device has no mute or volume control; leaving it as is")
        }
    }

    func restoreAfterRecording() {
        guard let change = pending else { return }
        pending = nil
        switch change {
        case .muted(let device):
            _ = Self.write(UInt32(0), device, Self.muteAddress)
        case .volume(let device, let previous):
            _ = Self.write(previous, device, Self.volumeAddress)
        }
    }

    // MARK: CoreAudio

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        let address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard let device = read(AudioDeviceID.self, AudioObjectID(kAudioObjectSystemObject), address),
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    private static func isSettable(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        guard AudioObjectHasProperty(object, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(object, &address, &settable) == noErr && settable.boolValue
    }

    private static func read<T>(_ type: T.Type, _ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> T? {
        var address = address
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, value) == noErr else { return nil }
        return value.pointee
    }

    private static func write<T>(_ value: T, _ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        return withUnsafeBytes(of: value) { bytes in
            AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(bytes.count), bytes.baseAddress!) == noErr
        }
    }
}
