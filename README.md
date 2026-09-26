# TalkToMyMac

A menu-bar dictation utility for macOS, built entirely on first-party Apple frameworks.

Two ways to dictate, each with its own configurable shortcut:

| Mode | Default | How it works |
|---|---|---|
| **Push to talk** | Fn | Hold while speaking; release to transcribe and paste. |
| **Toggle** | Fn+Space | Press to start, press again to stop and paste. |

Pressing Space while holding Fn *latches* the push-to-talk recording into toggle mode, so
you can start hands-on and let go. A quick tap of Fn, or Fn used with another key
(Fn+Delete, Fn+←, …), is treated as normal Fn use and discarded.

Fn shortcuts use an event tap, which needs the Accessibility permission (already required
for paste). Set System Settings → Keyboard → "Press 🌐 key to" → **Do Nothing**, or tapping
Fn will also open the emoji picker / switch input source.

Press **Esc** during either to discard the recording entirely (nothing is transcribed and
the audio file is deleted). Esc is only captured while recording, so it keeps working
normally in other apps the rest of the time.

Your speech is transcribed on-device with Apple's `SpeechAnalyzer`, cleaned up on-device by
Apple Intelligence (`SystemLanguageModel` / Foundation Models), and pasted at the cursor —
no network calls, no third-party models.

## Requirements

- macOS 26 or later
- Apple Intelligence enabled (System Settings → Apple Intelligence & Siri) for LLM formatting;
  without it, transcription still works and delivers the raw (unformatted) transcript.

## Permissions

- **Microphone** — to record audio for dictation.
- **Speech Recognition** — used by the on-device `Speech` framework.
- **Accessibility** — required only for auto-paste at the cursor.

All of these are requested at launch, so you're never stopped mid-dictation. If you decline
or need to change one later, the menu bar shows live Mic and Accessibility status, and the
Accessibility row is clickable to re-open the right System Settings pane. **After granting
Accessibility you generally need to relaunch the app** before synthetic keystrokes work.

## One-time setup: signing (do this first)

```sh
make setup-signing   # prompts for your login password
```

macOS TCC remembers permission grants against the app's *designated requirement*. With
ad-hoc signing that requirement is the binary's cdhash, so **every rebuild silently revokes
both Microphone and Accessibility access** — while the System Settings checkbox stays
visibly on, which makes it look like the app is broken.

`make setup-signing` creates a self-signed code-signing certificate named
`TalkToMyMac Dev` in your login keychain. `make build` picks it up automatically, producing
a requirement keyed to the certificate rather than the binary hash, so permissions survive
rebuilds. Without it, `make build` falls back to ad-hoc signing and prints a warning.

If you already granted permissions to an ad-hoc build, remove the stale TalkToMyMac entries
under Privacy & Security → Accessibility and → Microphone, then relaunch and re-grant once.

## Building

```sh
make build   # builds build/TalkToMyMac.app
make run     # builds and launches it
make test    # runs the TalkToMyMacCore unit tests
```

## Settings

Open Settings from the menu bar item (⌘,) to:

- Change either shortcut: click it and press the new combination (Esc cancels). A modifier
  is required, except for F1–F20 and Fn on its own (push to talk only). macOS can't detect clashes with other apps' shortcuts,
  so if one doesn't respond, something else probably owns it — pick another.
- Check on-device Speech model status and trigger a download.
- Enable/disable LLM formatting and pick a preset (Clean Up, Verbatim, Email, Code Comment,
  or a fully custom system prompt).
- Enable/disable auto-paste at the cursor.
