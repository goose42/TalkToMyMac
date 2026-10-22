import CoreAudio
import SwiftUI
import TalkToMyMacCore

/// The Audio settings tab: which microphone to record from, and what happens to the Mac's
/// sound output while dictating, and on which output devices.
@available(macOS 26.0, *)
struct AudioSettingsView: View {
    @Bindable var settings: FormattingSettings
    @State private var devices = DeviceList()

    var body: some View {
        Form {
            Section {
                Picker("Record from", selection: $settings.inputDevice) {
                    Text(systemDefaultMicrophoneTitle).tag(InputDeviceSelection.systemDefault)
                    Divider()
                    ForEach(microphoneRows) { device in
                        Text(microphoneTitle(device)).tag(InputDeviceSelection.device(uid: device.uid))
                    }
                }
            } header: {
                Text("Microphone")
            } footer: {
                Text("When Bluetooth headphones connect, your Mac usually switches to their "
                     + "microphone, which tends to sound worse. Pick a microphone to always record "
                     + "from it instead; if it isn't connected, the system default is used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("System audio", selection: $settings.systemAudioAction) {
                    ForEach(SystemAudioAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                }
                if settings.systemAudioAction == .dampen {
                    LabeledContent("Lower to \(Int((settings.systemAudioDampenLevel * 100).rounded()))% of current volume") {
                        Slider(value: $settings.systemAudioDampenLevel, in: 0.05...0.8, step: 0.05)
                            .frame(maxWidth: 200)
                    }
                }
            } header: {
                Text("While Recording")
            } footer: {
                Text("Sound playing from your speakers, like a meeting, can be picked up by the "
                     + "microphone and end up in your dictation. Mute silences it while you speak; "
                     + "Dampen turns it down instead. Either way it's restored when the recording "
                     + "ends, and if your Mac was already muted, it stays muted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if settings.systemAudioAction != .off {
                Section {
                    Picker("Apply when sound plays through", selection: $settings.systemAudioAllDevices) {
                        Text("Any device").tag(true)
                        Text("Only selected devices").tag(false)
                    }
                    if !settings.systemAudioAllDevices {
                        ForEach(deviceRows) { device in
                            Toggle(isOn: binding(for: device.uid)) {
                                Text(device.name)
                                if let note = note(for: device.uid) {
                                    Text(note)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Output Devices")
                } footer: {
                    Text("Applies to whichever device your Mac is currently playing through. "
                         + "Leave headphones unselected to keep listening while you dictate — "
                         + "their sound doesn't reach the microphone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { devices.start() }
        .onDisappear { devices.stop() }
        .onChange(of: devices.outputs) { _, connected in
            for device in connected where settings.systemAudioDeviceNames[device.uid] != device.name {
                settings.systemAudioDeviceNames[device.uid] = device.name
            }
        }
        .onChange(of: devices.inputs) { _, connected in
            for device in connected where settings.inputDeviceNames[device.uid] != device.name {
                settings.inputDeviceNames[device.uid] = device.name
            }
        }
    }

    private var systemDefaultMicrophoneTitle: String {
        guard let name = devices.inputs.first(where: { $0.uid == devices.currentInputUID })?.name else {
            return "System default"
        }
        return "System default (\(name))"
    }

    /// Connected microphones, then the chosen one if it isn't connected right now.
    private var microphoneRows: [AudioDevices.Device] {
        guard case .device(let uid) = settings.inputDevice,
              !devices.inputs.contains(where: { $0.uid == uid }) else { return devices.inputs }
        return devices.inputs + [AudioDevices.Device(uid: uid, name: settings.inputDeviceNames[uid] ?? uid)]
    }

    private func microphoneTitle(_ device: AudioDevices.Device) -> String {
        devices.inputs.contains(device) ? device.name : "\(device.name) (not connected)"
    }

    /// Connected devices, then selected devices that aren't connected right now.
    private var deviceRows: [AudioDevices.Device] {
        let connectedUIDs = Set(devices.outputs.map(\.uid))
        let absent = settings.systemAudioDeviceUIDs.subtracting(connectedUIDs).sorted().map {
            AudioDevices.Device(uid: $0, name: settings.systemAudioDeviceNames[$0] ?? $0)
        }
        return devices.outputs + absent
    }

    private func note(for uid: String) -> String? {
        if uid == devices.currentOutputUID { return "Current output" }
        if !devices.outputs.contains(where: { $0.uid == uid }) { return "Not connected" }
        return nil
    }

    private func binding(for uid: String) -> Binding<Bool> {
        Binding {
            settings.systemAudioDeviceUIDs.contains(uid)
        } set: { selected in
            if selected {
                settings.systemAudioDeviceUIDs.insert(uid)
            } else {
                settings.systemAudioDeviceUIDs.remove(uid)
            }
        }
    }
}

/// The Mac's input and output devices and which ones are current, kept up to date while
/// Settings shows them by listening for CoreAudio's device-list and default-device changes.
@MainActor
@Observable
private final class DeviceList {
    private(set) var inputs: [AudioDevices.Device] = []
    private(set) var outputs: [AudioDevices.Device] = []
    private(set) var currentInputUID: String?
    private(set) var currentOutputUID: String?

    private var listener: AudioObjectPropertyListenerBlock?

    private static let watched: [AudioObjectPropertySelector] = [
        kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice,
        kAudioHardwarePropertyDefaultOutputDevice,
    ]

    func start() {
        refresh()
        guard listener == nil else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        for selector in Self.watched {
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        }
        listener = block
    }

    func stop() {
        guard let listener else { return }
        for selector in Self.watched {
            var address = Self.address(selector)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
        self.listener = nil
    }

    private func refresh() {
        inputs = AudioDevices.list(.input)
        outputs = AudioDevices.list(.output)
        currentInputUID = AudioDevices.defaultDeviceUID(.input)
        currentOutputUID = AudioDevices.defaultDeviceUID(.output)
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}
