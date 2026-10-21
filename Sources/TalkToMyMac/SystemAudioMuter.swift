import CoreAudio
import OSLog
import TalkToMyMacCore

/// Mutes or dampens the default output device while a recording is in progress, as set on the
/// Audio settings tab (`settings.systemAudioPolicy`), so sound from speakers doesn't leak into
/// the dictation. The policy can limit this to chosen output devices, so headphones can be
/// left alone. The setting is read at the start of each recording, so changes in Settings take
/// effect on the next dictation.
///
/// Restores exactly what it changed, on the device it changed: a Mac that was already muted
/// stays muted, and switching output devices mid-recording doesn't leave the old one silent.
/// Devices without a mute control (some HDMI/USB outputs) are turned down to zero volume
/// instead, and devices without a volume control are muted rather than dampened.
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

    /// An output device as shown in Settings.
    struct OutputDevice: Identifiable, Hashable {
        let uid: String
        let name: String
        var id: String { uid }
    }

    private let settings: FormattingSettings
    private var pending: Change?
    private let logger = Logger(subsystem: "com.talktomymac.dictate", category: "SystemAudioMuter")

    init(settings: FormattingSettings) {
        self.settings = settings
    }

    func muteForRecording() {
        guard pending == nil, let device = Self.defaultOutputDevice(),
              let uid = Self.uid(of: device) else { return }

        switch settings.systemAudioPolicy.plan(forDeviceUID: uid) {
        case .leaveAlone:
            return
        case .mute:
            if !mute(device) && !setVolume(device) { logNoControls() }
        case .lower(let fraction):
            if !setVolume(device, scaledBy: fraction) {
                if mute(device) {
                    logger.notice("Output device has no volume control; muted it instead of dampening")
                } else {
                    logNoControls()
                }
            }
        }
    }

    /// Mutes `device` if it has a mute control, returning whether it does. An already-muted
    /// device is left as is, with nothing to undo.
    private func mute(_ device: AudioDeviceID) -> Bool {
        guard Self.isSettable(device, Self.muteAddress) else { return false }
        guard Self.read(UInt32.self, device, Self.muteAddress) == 0 else { return true }
        if Self.write(UInt32(1), device, Self.muteAddress) {
            pending = .muted(device)
        }
        return true
    }

    /// Sets `device`'s volume to `fraction` of its current value if it has a volume control,
    /// returning whether it does. A device already at zero is left as is.
    private func setVolume(_ device: AudioDeviceID, scaledBy fraction: Double = 0) -> Bool {
        guard Self.isSettable(device, Self.volumeAddress) else { return false }
        guard let volume = Self.read(Float32.self, device, Self.volumeAddress), volume > 0 else { return true }
        let target = SystemAudioPolicy.dampenedVolume(current: volume, level: fraction)
        if Self.write(target, device, Self.volumeAddress) {
            pending = .volume(device, previous: volume)
        }
        return true
    }

    private func logNoControls() {
        logger.notice("Default output device has no mute or volume control; leaving it as is")
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

    /// Every device that can play sound, in CoreAudio's order.
    static func outputDevices() -> [OutputDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { device in
            guard hasOutputStreams(device), let uid = uid(of: device) else { return nil }
            return OutputDevice(uid: uid, name: string(device, kAudioObjectPropertyName) ?? uid)
        }
    }

    /// The UID of the device sound currently plays through.
    static func defaultOutputDeviceUID() -> String? {
        defaultOutputDevice().flatMap(uid(of:))
    }

    private static func uid(of device: AudioDeviceID) -> String? {
        string(device, kAudioDevicePropertyDeviceUID)
    }

    private static func hasOutputStreams(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        let address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        // CoreAudio hands back a +1 reference for CFString properties.
        return read(Unmanaged<CFString>.self, object, address)?.takeRetainedValue() as String?
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
