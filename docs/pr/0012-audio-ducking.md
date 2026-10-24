# #0012 — Audio settings tab and build dependency check

- Branch: `jv.audio-ducking` · Merged: 2026-10-21 · Commits: `4f4824f`, `bc649ee`

## Why
Meeting audio from the speakers is picked up by the mic and ends up in dictations. A hard mute was the only option (PR #1). Separately, builds failed confusingly on machines without a proper Xcode setup.

## What changed
- New **Audio** tab (second in the sidebar) replaces General's "Mute system audio while recording" toggle:
  - While recording: Off / Mute / Dampen. Dampen lowers volume to 5–80% of current (default 20%) and restores the exact previous level.
  - Output devices: any device, or only selected ones (e.g. leave headphones alone). Devices are remembered by CoreAudio UID and listed as "Not connected" when unplugged; the list updates live.
  - Acts on the default output device; an already-muted Mac stays muted; devices without volume control are muted when Dampen is chosen.
  - The old toggle migrates to Mute on any device.
- `make install`, `make run` and `make check-deps` run `scripts/check-dependencies.sh` first: macOS 26+, Xcode 26+ (opens the App Store page if missing/old), Xcode as the active developer directory (offers `xcode-select --switch`), license accepted (offers to accept), SDK and Swift compiler usable. The signing setup's OpenSSL commands were checked against macOS's LibreSSL, so Homebrew isn't needed.

## Files touched
- Core: `SystemAudioPolicy.swift`, `SettingsPane.swift`
- App: `AudioSettingsView.swift`, `SystemAudioMuter.swift`, `FormattingSettings.swift`, `SettingsWindowController.swift`
- Build: `Makefile`, `scripts/check-dependencies.sh`, `README.md`

## Decisions & trade-offs
Decision logic lives in Core (`SystemAudioPolicy`) so it is testable; `SystemAudioMuter` only applies it via CoreAudio.

## Tests
422 tests passed (`SystemAudioPolicyTests`, updated `SettingsPaneTests`). Mute/Dampen tried by hand; missing-Xcode simulated. The switch-to-Xcode and license prompts were not exercised.

## Follow-ups / known gaps
PR #13 adds a Microphone section to this tab.
