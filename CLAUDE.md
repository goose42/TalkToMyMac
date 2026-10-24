# TalkToMyMac

macOS menu-bar dictation app (Swift 6, SwiftPM, macOS 26+). Speech is transcribed on-device
(Parakeet via FluidAudio, or Apple `SpeechAnalyzer`), optionally cleaned up by a formatter
(Foundation Models, Groq, or OpenRouter), and pasted at the cursor.

## Rules

- **Branching:** always create a branch prefixed with `jv.` (e.g. `jv.audio-ducking`) before
  making any changes to the repo. Never commit directly to `main`.
- **TDD:** always follow a red → green → refactor approach. Write a failing test first and
  confirm it fails (red), write the minimum code to pass (green), then refactor with tests
  still green.
- **PR docs:** every PR must add `docs/pr/NNNN-<slug>.md` (PR number zero-padded to 4 digits,
  slug = branch name without `jv.`) describing the change, following the template in
  `docs/pr/README.md`. It is an agent-readable history of the repo: record why the change was made,
  what changed, key decisions and trade-offs, tests, and known gaps. Create the PR first to get its
  number, then commit the doc to the same branch before merging. Keep it current if the PR changes.
- **UI:** all UI changes must adhere to Apple's Human Interface Guidelines for macOS 27.

## Layout

- `Sources/TalkToMyMacCore` — pure logic, no UI dependencies. **The only target with tests**
  (`Tests/TalkToMyMacCoreTests`), so put testable logic here and keep the app target thin.
- `Sources/TalkToMyMac` — AppKit/SwiftUI app executable (views, audio, hotkeys, providers).
- `docs/pr` — one markdown file per PR; the repo's agent-readable history (see `docs/pr/README.md`).

## Commands

- `make test` — run unit tests
- `make build` — build and sign `build/TalkToMyMac.app`
- `make run` / `make install` — launch / install to `/Applications` (both run `check-deps`)
- `make setup-signing` — one-time; creates the "TalkToMyMac Dev" identity so Microphone and
  Accessibility grants survive rebuilds
