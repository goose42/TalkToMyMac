# #0005 — Deterministic dictionary replacement with a per-occurrence picker

- Branch: `jv.deterministic-dictionary` · Merged: 2026-10-16 · Commits: `e2b2dcc`, `7b948a6`

## Why
Letting the formatting LLM apply the dictionary was unreliable and gave the user no way to undo a wrong replacement. Replacement is now deterministic and reviewable.

## What changed
- The formatting LLM no longer sees the dictionary (no dictionary JSON, rules or `{{DICTIONARY}}` placeholder in the Coding Dictation prompt or `FormattingInstructions`).
- `CleanupRouter`: dictionary sounds-like fixes always run, even with deterministic cleanup off.
- `ReplacementReview` (Core) matches each replacement in the raw transcript to the written form in the cleaned/pasted text by order of appearance, skipping terms the speech model already got right; if formatting changed the count it offers every occurrence. Provides per-occurrence revert, context snippets and a minimal tail edit.
- Floating indicator: after a paste with replacements the dot becomes a count pill. Clicking opens a picker that rewrites the paste in place (⇧← to select the tail, then ⌘V). The offer expires on typing or clicking in another app, or a new recording; our own synthetic keystrokes are tagged so they don't expire it.
- Terminals: ⇧← doesn't select text there, so an optional `TranscriptReviewing` pipeline step pauses after cleanup and shows the picker with Paste and Cancel before pasting. Cancel still saves the transcript.
- Fixed an unsafe-pointer warning in `SystemAudioMuter`.

## Files touched
- Core: `ReplacementReview.swift`, `DictionaryReplacement.swift`, `CodingDictationPrompt.swift`, `FormattingInstructions.swift`, `RecorderController.swift`, `Protocols.swift`
- App: `FloatingIndicator.swift`, `PasteDelivery.swift`, `TerminalReviewer.swift`, `CleanupRouter.swift`
- Other: `dictation_cleanup_prompt.md`, `README.md`

## Decisions & trade-offs
- Existing installs keep a saved Coding Dictation prompt with the old dictionary rules and a literal `{{DICTIONARY}}`; users must press **Reset** to pick up the new text.

## Tests
300 tests passed; `ReplacementReviewTests` added; tests were written first for most of the work. Not checked by hand at merge: in-place rewrite, terminal Paste/Cancel flow, drag vs click on the indicator.

## Follow-ups / known gaps
PR #14 adds a menu on the same indicator and shares its click routing.
