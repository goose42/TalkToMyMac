# #0013 — Add a Microphone setting to pick the input device

- Branch: `jv.microphone-selection` · Merged: 2026-10-22 · Commits: `81f9b0a`

## Why
When Bluetooth headphones connect, macOS usually switches to their microphone, which tends to sound worse.

## What changed
The Audio tab has a **Microphone → Record from** picker:
- **System default** (shows the current mic name): existing behavior, and the default.
- **A specific microphone**: always record from it, remembered by UID and listed as "(not connected)" when unplugged. If unavailable, recording falls back to the system default so dictation keeps working.

Applies to dictation and the dictionary's Record Pronunciation sheet.

## Files touched
- Core: `InputDeviceSelection.swift` (selection, persistence, fallback)
- App: `AudioDevices.swift` (shared CoreAudio input/output queries, moved out of `SystemAudioMuter`), `AudioCapture.swift`, `AudioSettingsView.swift`, `PronunciationRecorderView.swift`, `DictionaryView.swift`, `FormattingSettings.swift`

## Decisions & trade-offs
`AudioCapture` points the engine's input unit at the chosen device before each recording and creates a fresh engine only when the device changes, so the system-default path is unchanged.

## Tests
427 tests passed (5 new `InputDeviceSelectionTests`). Manually verified AirPods + built-in mic, unplugging, and switching back.

## Follow-ups / known gaps
None recorded.
