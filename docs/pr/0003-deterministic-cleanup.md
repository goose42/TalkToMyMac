# #0003 — Add deterministic (non-LLM) transcript cleanup

- Branch: `jv.deterministic_cleanup` · Merged: 2026-10-14 · Commits: `b180eb5`

## Why
Cleanup of fillers, voice commands and so on should work without an LLM. The stages are ported from BetterWispr's post-processing pipeline.

## What changed
An opt-in **Cleanup** phase (checkbox in Settings → Formatting) between transcription and LLM formatting. It is independent of whether LLM formatting is on: with the LLM off the cleaned text is delivered, with it on the LLM receives the cleaned text.

Stages:
1. Light cleanup (`TranscriptCleaner`): fillers, self-repairs, stutters.
2. Dictionary command fixes (entries whose written form is a spoken command, e.g. "question mark").
3. Voice commands and spoken numbers, English only ("comma", "new line", "scratch that", @/#/%, domains, "two hundred fifty thousand" → 250,000).
4. Email layout, English only ("write an email to Sam saying …").
5. Dictionary terms: `sounds_like` → `written`, single pass, whole-word matching, no cascading.

## Files touched
- Core: `DeterministicCleanup.swift`, `TranscriptCleaner.swift`, `VoiceCommands.swift`, `SpokenNumbers.swift`, `EmailDictation.swift`, `DictionaryReplacement.swift`, `RecorderController.swift`, `Models.swift`, `Protocols.swift`
- App: `CleanupRouter.swift`, `FormattingSettings.swift`, `FormattingView.swift`, `TranscriptionStore.swift`

## Decisions & trade-offs
- Off by default; stays enabled when LLM formatting is off.
- `PipelineResult.cleanedText` records the output; history still stores the raw transcript.
- A dictation that cleans to nothing (just "um") is treated as silence: nothing delivered or stored.
- The short-dictation word count uses cleaned text. `words_changed` is measured from the LLM's input, so it counts only LLM edits.
- The dictionary pass ignores `context`, `inflect` and `format_as_code`, which stay LLM concerns (changed in PR #5).

## Tests
272 tests passed, including BetterWispr's cleaner, voice-command, number and email cases ported to XCTest. Manual dictation check left unchecked in the PR.

## Follow-ups / known gaps
PR #5 removed the dictionary from the LLM; PR #7 restricts full cleanup to English.
