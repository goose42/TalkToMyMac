import CoreAudio
import TalkToMyMacCore

/// CoreAudio queries for the Mac's audio devices, shared by `SystemAudioMuter` (output),
/// `AudioCapture` (input) and the Audio settings tab.
enum AudioDevices {
    /// A device as shown in Settings.
    struct Device: Identifiable, Hashable {
        let uid: String
        let name: String
        var id: String { uid }
    }

    enum Direction {
        case input, output

        fileprivate var streamScope: AudioObjectPropertyScope {
            self == .input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
        }

        fileprivate var defaultDeviceSelector: AudioObjectPropertySelector {
            self == .input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
        }
    }

    /// Every device that can record (`.input`) or play (`.output`) sound, in CoreAudio's order.
    static func list(_ direction: Direction) -> [Device] {
        allDeviceIDs().compactMap { device in
            guard hasStreams(device, direction), let uid = uid(of: device) else { return nil }
            return Device(uid: uid, name: string(device, kAudioObjectPropertyName) ?? uid)
        }
    }

    /// UIDs of the input devices, read from CoreAudio once and kept until `AudioDeviceWatcher`
    /// sees the device list change. Starting a recording used to re-read every device on the
    /// main thread, which stalls while a Bluetooth device is changing profile.
    static let cachedInputUIDs = InvalidatingCache<[String]> { list(.input).map(\.uid) }

    /// UID of the Mac's own microphone, if it has one. Looked up once: it never changes, and
    /// looking it up is the only device scan built-in-only mode does.
    static let builtInInputUID: String? = allDeviceIDs().first { device in
        hasStreams(device, .input) && transportType(device) == kAudioDeviceTransportTypeBuiltIn
    }.flatMap(uid(of:))

    /// The device the Mac currently records from or plays through.
    static func defaultDevice(_ direction: Direction) -> AudioDeviceID? {
        let address = AudioObjectPropertyAddress(mSelector: direction.defaultDeviceSelector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard let device = read(AudioDeviceID.self, AudioObjectID(kAudioObjectSystemObject), address),
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    static func defaultDeviceUID(_ direction: Direction) -> String? {
        defaultDevice(direction).flatMap(uid(of:))
    }

    /// The connected device with `uid`, if there is one.
    static func device(uid: String) -> AudioDeviceID? {
        allDeviceIDs().first { self.uid(of: $0) == uid }
    }

    static func uid(of device: AudioDeviceID) -> String? {
        string(device, kAudioDevicePropertyDeviceUID)
    }

    static func read<T>(_ type: T.Type, _ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> T? {
        var address = address
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, value) == noErr else { return nil }
        return value.pointee
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func transportType(_ device: AudioDeviceID) -> UInt32? {
        read(UInt32.self, device, AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                                             mScope: kAudioObjectPropertyScopeGlobal,
                                                             mElement: kAudioObjectPropertyElementMain))
    }

    private static func hasStreams(_ device: AudioDeviceID, _ direction: Direction) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: direction.streamScope,
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
}

/// Keeps `cachedInputUIDs` fresh by listening for CoreAudio device and default-device changes
/// (a headset connecting, switching profile or leaving). Callbacks run on a private queue.
final class AudioDeviceWatcher: @unchecked Sendable {
    static let shared = AudioDeviceWatcher()

    private let queue = DispatchQueue(label: "com.talktomymac.audio-device-watcher")
    private var listener: AudioObjectPropertyListenerBlock?

    private static let watched: [AudioObjectPropertySelector] = [
        kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice,
        kAudioHardwarePropertyDefaultOutputDevice,
    ]

    /// Starts listening.
    func start() {
        guard listener == nil else { return }
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            AudioDevices.cachedInputUIDs.invalidate()
        }
        for selector in Self.watched {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
        }
        listener = block
    }

    /// Stops listening; the system then gets no callbacks from us at all.
    func stop() {
        guard let listener else { return }
        for selector in Self.watched {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
        }
        self.listener = nil
    }
}
