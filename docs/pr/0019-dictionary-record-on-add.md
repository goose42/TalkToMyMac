# #0019 — Open pronunciation recorder on add; allow custom sentence

- Branch: `jv.dictionary-record-on-add` · Merged: not yet · Commits: 3afe907

## Why
Recording a pronunciation was a separate manual step (open a word, click "Record Pronunciation…").
The user wanted the recorder to appear the moment a word is added. They also wanted to replace the
fixed second-step sentence ("I'm working with <word> today"), which may not fit the word.

## What changed
- Adding a dictionary word opens its detail page with the pronunciation recorder sheet already up.
  Cancelling keeps the word; if the transcriber isn't ready, only the detail page shows.
- The recorder's sentence step has a text field prefilled with the default sentence. The user can
  edit it. If the edit drops the word, a red hint shows and Record is disabled.

## Files touched
- Core: `PronunciationSentence.swift` (new), `PronunciationProbe.swift` (custom carrier).
- App: `DictionaryView.swift` (`addWord`, `EntryDetailView.opensRecorderOnAppear`),
  `PronunciationRecorderView.swift` (`sentenceDraft`, `recordControls`).
- Tests: `PronunciationSentenceTests.swift` (new).

## Decisions & trade-offs
- Reused the existing detail-page sheet rather than hoisting a sheet to `DictionaryView`; add-word
  sets `selection` and a flag. The sheet is presented in a `Task` on the next run-loop turn because
  a sheet set during the page swap can be dropped.
- `PronunciationProbe` cuts the term out of the transcript using the carrier's prefix and suffix, so
  a custom sentence is split around the word (case-insensitive, first match) and passed as the
  carrier. Defaults are unchanged.

## Tests
`PronunciationSentenceTests` (10): default sentence, resolve (trim, nil/empty/whitespace fallback),
`carrier(in:around:)`, and `extractSlot` with a custom prefix/suffix. `make test` passes (464) and
`swift build` compiles the app. The popup timing and text field were not tried in the running app.

## Follow-ups / known gaps
- The custom sentence is not persisted; it applies to the current recording only. Saving it per
  entry would change the `DictionaryEntry` file format and import/export.
