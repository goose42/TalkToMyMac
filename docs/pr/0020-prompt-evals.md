# #0020 — Compile prompts from Markdown and add a prompt eval harness

- Branch: `jv.prompt-evals` · Merged: not yet · Commits: a77be32, 404fd15

## Why
Prompts were Swift string literals. The coding prompt was also kept in `dictation_cleanup_prompt.md`
and copied into Swift by hand. That made prompts awkward to edit and there was no way to measure
whether a prompt change helped. The user wanted prompts defined as Markdown and compiled into the
app, plus a standalone way to check, with their real dictionary and the Apple on-device model,
that a prompt turns their input into the output they want.

## What changed
- Built-in prompts live in `Sources/TalkToMyMacCore/Prompts/*.md` (`coding`, `clean-up`,
  `verbatim`, `email`, `code-comment`, `dictionary-entry`) and are compiled into a generated
  `PromptLibrary` (`public static let` per file, plus `all` keyed by file name). The text is
  unchanged.
- `PromptPreset.fileName` maps a preset to its file.
- New standalone package `evals/` with the `ttm-eval` CLI. It runs a prompt over
  `evals/cases/<suite>.jsonl` (cleanup with the dictionary, then the on-device model with the
  app's settings), prints a table, writes `evals/results/<suite>-<timestamp>.json`, and can fail
  under a `--threshold`. It ships seed cases for coding, clean-up and verbatim.
- `make eval SUITE=… ARGS=…` and `make eval-test`.

## Files touched
- Build: `Package.swift` (tools 6.1, products `TalkToMyMacCore` and `PromptCodegen`, plugin and
  codegen targets), `Plugins/PromptCompilerPlugin`, `Sources/PromptCompiler`, `Makefile`.
- Core: `Sources/PromptCodegen`, `Prompts/*.md` + `Prompts/README.md`, `PromptPresets.swift`,
  `DictionaryEntryPrompt.swift`, `FormattingInstructions.swift` (temperature, token limit),
  `DeterministicCleanup.swift` (`clean(_:dictionary:fullCleanup:language:)`). Removed
  `CodingDictationPrompt.swift` and `dictation_cleanup_prompt.md`.
- App: `CleanupRouter.swift` and `FoundationModelFormatter.swift` now call the shared Core code.
- Evals: `evals/Package.swift`, `Sources/EvalKit` (cases, options, scoring, judge, dictionary and
  prompt resolution, reports), `Sources/ttm-eval/main.swift`, `Tests/EvalKitTests`, `cases/`.
- Docs: `README.md`, `CLAUDE.md`, `evals/README.md`.

## Decisions & trade-offs
- **Codegen plugin, not SwiftPM resources.** The Makefile copies only the binary into the
  `.app`, so a `Bundle.module` resource bundle would be missing from installed builds. Generated
  source compiles the text in and needs no runtime loading.
- **Raw string literals with one more `#` than the longest `#` run in the text**, so no prompt
  content can end the literal or form an escape.
- **Byte-identical prompts, pinned by SHA-256.** `PromptPreset.isEdited` compares saved text with
  the built-in text, so any accidental change would flag every user's prompt as edited. The
  `.md` files were dumped from the old strings by a throwaway test to guarantee this. Update a
  hash only when you mean to change a prompt.
- **Evals as a separate package** depending on the root via `.package(name: "TalkToMyMac", path: "..")`.
  It stays out of `make build` and `make test`. The explicit name lets it resolve in worktrees
  whose folder isn't `TalkToMyMac`.
- **Shared code over copies.** The cleaning decision (`DeterministicCleanup.clean`) and the
  generation settings moved into Core so the app and the evals can't drift. The model and
  guardrails construction is still duplicated in `ttm-eval/main.swift`, because FoundationModels
  can't be imported into Core.
- **Scoring:** a case passes on an exact match (whitespace-normalized per line; line breaks,
  case and punctuation count) or on a judge PASS. Word similarity uses `WordDiff`. The judge is
  the same on-device model, so it's noisy.
- **JSONL cases,** at the user's choice (Markdown cases were also offered).
- The tools version bump to 6.1 is needed for `Target.directoryURL` in the plugin.

## Tests
- `PromptCodegenTests`: identifiers, trailing newline and CRLF handling, delimiter choice,
  sorted output with an `all` table, duplicate-identifier error.
- `PromptPresetTests`: hash pins, presets read from `PromptLibrary`, `all` lookup, `fileName`.
- `FormattingInstructionsTests`: generation settings. `DeterministicCleanupTests`: `clean(...)`.
- `EvalKitTests` (43): JSONL parsing and errors, scoring, judge-reply parsing, dictionary-source
  precedence, prompt resolution, CLI options, summary, table and JSON report.
- By hand: `make build` (prompt text present in the binary). `make eval SUITE=coding ARGS=--judge`
  with the real dictionary gave 9/10. The miss was `empty-noise`: for `um uh` the model returns
  "```" instead of an empty string. A weak draft prompt scored 1/10, and `--threshold 0.8` exited 1.

## Follow-ups / known gaps
- The coding prompt returns "```" for pure-noise input (found by the evals; prompt not changed here).
- Evals always format. They ignore the app's minimum-word skip and treat language as auto-detected.
- Only the on-device model is evaluated. Groq and OpenRouter could be added behind `--provider`.
- The seed cases are few, and half of the coding cases are copies of the prompt's own examples.
  Add real dictations from Transcriptions history.
