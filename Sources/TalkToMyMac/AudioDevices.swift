import CoreAudio

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
