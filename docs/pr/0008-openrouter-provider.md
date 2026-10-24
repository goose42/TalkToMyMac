# #0008 — Add OpenRouter provider, Groq models, indicator notices, 4s formatting deadline and transcript stepping

- Branch: `jv.openrouter-provider` · Merged: 2026-10-17 · Commits: `7214c17`, `cd1d145`, `fc81a1d`

## Why
Add a free-model formatting option and make remote-formatting failures non-blocking. Further rationale not recorded.

## What changed
- **OpenRouter:** chat-completions client (`OpenRouterResponses`), `OpenRouterFormatter`, configuration page (Keychain account `openrouter`, same service as Groq), model picker and pricing. Models are all `:free` (Nemotron 3 Ultra, Nemotron 3.5 Lightning (default), Inkling Small, Gemma 4 26B, North Mini Code, LFM 2.5). HTTP 401/402/429 map to readable errors.
- **Groq:** added GPT-OSS 120B and Qwen 3.8 27B (replacing unavailable Llama models). `reasoning` is sent only to GPT-OSS models. Qwen has no published price, so fields start at $0 and are editable.
- **Indicator notices:** `IndicatorNotice` + `NoticePresenting`; the dot grows into a card with a 10 s countdown bar; click dismisses. Panel position saved as a bottom-centre anchor, migrated from the old key.
- **Pause on failure:** a failed remote call pauses that provider for 1 hour (persisted); Settings shows a note with **Resume Formatting Now**, Models shows "Paused".
- **4 s formatting deadline** for on-device, Groq and OpenRouter. Past it, cleaned text is pasted unformatted with a notice. A timeout does not trigger the pause. `withDeadline` returns on time even if the operation ignores cancellation.
- `PriceEditor` extracted and shared.
- **Transcript stepping:** ↑/↓ on the detail page moves to newer/older dictation across the whole history; list ties break by id so order matches stepping.

## Files touched
- Core: `OpenRouterResponses.swift`, `Deadline.swift`, `FormattingPause.swift`, `IndicatorNotice.swift`, `GroqResponses.swift`, `FormattingModel.swift`
- App: `OpenRouterFormatter.swift`, `OpenRouterConfigurationView.swift`, `PriceEditor.swift`, `GroqFormatter.swift`, `FormattingSettings.swift`, `TranscriptionsView.swift`, `TranscriptionStore.swift`

## Decisions & trade-offs
- Free OpenRouter models need "allow providers that may train on inputs" enabled at openrouter.ai/settings/privacy.

## Tests
374 tests passed (new OpenRouter, Groq catalog, notice, pause and deadline tests); release build clean. Unchecked at merge: failure notice and pause flow, hung-model deadline, dragged indicator position surviving upgrade, stepping across a page boundary.

## Follow-ups / known gaps
PR #10 exists because of the 4 s deadline.
