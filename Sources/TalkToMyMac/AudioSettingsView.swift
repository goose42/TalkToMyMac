import CoreAudio
import SwiftUI
import TalkToMyMacCore

/// The Audio settings tab: what happens to the Mac's sound output while dictating, and on
/// which output devices.
@available(macOS 26.0, *)
struct AudioSettingsView: View {
    @Bindable var settings: FormattingSettings
    @State private var devices = OutputDeviceList()

    var body: some View {
        Form {
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
        .onChange(of: devices.connected) { _, connected in
            for device in connected where settings.systemAudioDeviceNames[device.uid] != device.name {
                settings.systemAudioDeviceNames[device.uid] = device.name
            }
        }
    }

    /// Connected devices, then selected devices that aren't connected right now.
    private var deviceRows: [SystemAudioMuter.OutputDevice] {
        let connectedUIDs = Set(devices.connected.map(\.uid))
        let absent = settings.systemAudioDeviceUIDs.subtracting(connectedUIDs).sorted().map {
            SystemAudioMuter.OutputDevice(uid: $0, name: settings.systemAudioDeviceNames[$0] ?? $0)
        }
        return devices.connected + absent
    }

    private func note(for uid: String) -> String? {
        if uid == devices.currentUID { return "Current output" }
        if !devices.connected.contains(where: { $0.uid == uid }) { return "Not connected" }
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

/// The Mac's output devices and which one is current, kept up to date while Settings shows
/// them by listening for CoreAudio's device-list and default-output changes.
@MainActor
@Observable
private final class OutputDeviceList {
    private(set) var connected: [SystemAudioMuter.OutputDevice] = []
    private(set) var currentUID: String?

    private var listener: AudioObjectPropertyListenerBlock?

    private static let watched: [AudioObjectPropertySelector] = [
        kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice,
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
        connected = SystemAudioMuter.outputDevices()
        currentUID = SystemAudioMuter.defaultOutputDeviceUID()
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}
