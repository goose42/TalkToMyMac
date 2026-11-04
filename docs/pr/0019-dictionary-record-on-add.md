# #0019 — Open pronunciation recorder on add; allow custom sentence; no model-guessed sound-alikes

- Branch: `jv.dictionary-record-on-add` · Merged: not yet · Commits: 3afe907

## Why
Recording a pronunciation was a separate manual step (open a word, click "Record Pronunciation…").
The user wanted the recorder to appear the moment a word is added. They also wanted to replace the
fixed second-step sentence ("I'm working with <word> today"), which may not fit the word.

## What changed
- Adding a dictionary word opens its detail page with the pronunciation recorder sheet already up.
  Cancelling keeps the word; if the transcriber isn't ready, only the detail page shows.
- The model no longer guesses "Heard as" (`soundsLike`) forms. Generation still fills type, context
  and the code/inflect flags. Heard-as forms now come only from the user and from recordings.
- The recorder's sentence step has a text field prefilled with the default sentence. The user can
  edit it. If the edit drops the word, a red hint shows and Record is disabled.

## Files touched
- Core: `PronunciationSentence.swift` (new), `PronunciationProbe.swift` (custom carrier),
  `DictionaryEntryPrompt.swift` (no soundsLike), `DictionaryEditor.swift` (`sanitized`, `addSoundsLike`).
- App: `DictionaryView.swift` (`addWord`, `EntryDetailView.opensRecorderOnAppear`),
  `PronunciationRecorderView.swift` (`sentenceDraft`, `recordControls`),
  `FoundationModelEntryGenerator.swift` (dropped `soundsLike` from the generated struct).
- Tests: `PronunciationSentenceTests.swift` (new).

## Decisions & trade-offs
- Reused the existing detail-page sheet rather than hoisting a sheet to `DictionaryView`; add-word
  sets `selection` and a flag. The sheet is presented in a `Task` on the next run-loop turn because
  a sheet set during the page swap can be dropped.
- `PronunciationProbe` cuts the term out of the transcript using the carrier's prefix and suffix, so
  a custom sentence is split around the word (case-insensitive, first match) and passed as the
  carrier. Defaults are unchanged.

- A finished generation keeps the entry's existing `soundsLike` instead of replacing it (previously
  the model's list overwrote it). `addSoundsLike` no longer goes through `update`, so recording
  while a generation is pending doesn't cancel it. Before this, finishing a recording right after
  adding a word discarded the generated type and context. `maxSoundsLike` was removed with the
  generated list.
- Existing dictionaries keep any `sounds_like` already saved; only new generation changed.

## Tests
`PronunciationSentenceTests` (10): default sentence, resolve (trim, nil/empty/whitespace fallback),
`carrier(in:around:)`, and `extractSlot` with a custom prefix/suffix. Editor tests: a suggestion's
`soundsLike` is ignored, generation keeps recorded forms, and `addSoundsLike` doesn't cancel a
pending suggestion. Prompt test: the instructions don't mention `soundsLike`. `make test` passes (466) and
`swift build` compiles the app. The popup timing and text field were not tried in the running app.

## Follow-ups / known gaps
- The custom sentence is not persisted; it applies to the current recording only. Saving it per
  entry would change the `DictionaryEntry` file format and import/export.
