# #0017 — Record with an input-only capture session so Bluetooth output no longer stalls dictation

- Branch: `jv.bluetooth-responsiveness` · Merged: not yet · Commits: e91cfd1

## Why
With a Bluetooth headset connected, dictation dropped words and the widget waveform stuttered; with no
Bluetooth device it was fine. The first hypotheses (aggressive device polling, A2DP→HFP profile switch
on the Bluetooth *mic*, slow CoreAudio calls on the main thread) were addressed but did not fix it —
the problem persisted even when forced to the built-in mic. Actual root cause: `AVAudioEngine` drives
one audio unit for input and output, so `engine.start()` also opened the default *output* device (the
headset), tying capture to its clock and latency.

## What changed
- `AudioCapture` records with an input-only `AVCaptureSession` (mono float32 at the device rate). It
  never opens an output device. This is the fix that resolved the symptom.
- `start()`/`stop()` only flip a flag and queue work on a serial `AudioWorkQueue`; `SystemAudioMuter`
  uses the same queue, so the Fn event tap callback returns immediately and mute/restore stay ordered
  with recording. A failed start calls `onStartFailure`, which cancels the recording.
- `finishedRecording()` replaces reading samples directly; the pipeline and pronunciation recorder await it.
- Input device UIDs are cached (`InvalidatingCache`) and invalidated by `AudioDeviceWatcher`.
- New Audio setting "Built-in microphone only": always records from the built-in mic, stops the watcher,
  skips device scans and output muting. Troubleshooting aid; see gaps below.
- `FunctionKeyMonitor`: after the event tap is re-enabled following a timeout, Fn is treated as released
  if it was let go in the gap, so a hold recording can't run on.

## Files touched
- Core: `AudioWorkQueue`, `InvalidatingCache`, `InputRouting` (`targetUID`)
- App: `AudioCapture`, `AudioDevices` (cache, built-in lookup, `AudioDeviceWatcher`), `SystemAudioMuter`,
  `AppDelegate`, `FormattingSettings`, `AudioSettingsView`, `FunctionKeyMonitor`, `PronunciationRecorderView`
- Tests: `AudioWorkQueueTests`, `InvalidatingCacheTests`, `InputRoutingTests`

## Decisions & trade-offs
- `AVCaptureSession` over an input-only HAL unit: much less code; `AVCaptureDevice(uniqueID:)` accepts the
  CoreAudio UID already used for mic selection.
- Engine pre-building/rebuilding on device change was tried and removed once the engine was gone.
- Muting output still touches the Bluetooth output volume (on the audio queue, off main).
- Lesson: with a Bluetooth output, avoid anything that starts an `AVAudioEngine`/AUHAL for input only.

## Tests
New Core tests (written red-first) for the queue, cache and mic-selection logic; 454 tests pass. The
capture session and Fn recovery are not unit-testable (app target); verified by hand with a Bluetooth headset.

## Follow-ups / known gaps
- "Built-in microphone only" no longer fixes anything the capture-session change didn't; candidate for removal.
- `AudioSettingsView`'s `DeviceList` still re-reads devices on the main thread while Settings is open.
- Fn-tap recovery has no automated test.
