# Prompt evals

A standalone tool for measuring how well a formatting prompt turns your raw dictation into the
text you want. It isn't part of the app build.

For each case it does what the app does:

1. **Deterministic cleanup with your dictionary.** This uses `DeterministicCleanup.clean`, the
   same function the app's `CleanupRouter` calls. By default it uses the app's own dictionary:
   the `dictionary.json` in the folder chosen in Settings, falling back to the copy in the app's
   settings.
2. **Apple's on-device model** (`SystemLanguageModel`, permissive content-transformation
   guardrails), with the prompt as instructions, the same `<transcript>` user turn,
   temperature and token limit as `FoundationModelFormatter`. Each case gets a fresh session.
3. **Scoring** against your expected text.

## Running

```sh
make eval SUITE=coding                                  # evals/cases/coding.jsonl
make eval SUITE=coding ARGS="--judge --runs 3"
swift run --package-path evals ttm-eval evals/cases/coding.jsonl --prompt ~/draft.md
make eval-test                                          # the harness's own unit tests
```

| Option | Meaning |
| --- | --- |
| `--preset <name>` | Built-in prompt to test, by file name (`coding`, `clean-up`, `verbatim`, `email`, `code-comment`). Defaults to the one named like the case file. |
| `--prompt <file.md>` | Test a prompt file instead, e.g. a draft. It's read the way the build reads `Prompts/*.md`. |
| `--dictionary <file>` | Use this `dictionary.json` instead of the app's. |
| `--no-dictionary` | Don't use a dictionary. |
| `--no-cleanup` | Skip full deterministic cleanup. The dictionary still applies, as in the app when cleanup is off. |
| `--judge` | For outputs that don't match exactly, ask the on-device model whether they're still acceptable. |
| `--runs <n>` | Run each case n times to see how much the output varies. |
| `--threshold <0-1>` | Exit 1 if the pass rate is below this (useful in scripts). |
| `--filter <text>` | Only run cases whose id contains this. |

The output is a table with one row per run, showing the expected and actual text under each miss.
A JSON report with every input, cleaned input, output, score and judge verdict goes to
`evals/results/<suite>-<timestamp>.json`, which is gitignored.

## Writing cases

`evals/cases/<suite>.jsonl` has one JSON object per line. Blank lines and lines starting with `//`
are skipped.

```json
{"id": "scratch-that", "input": "add a retry scratch that add backoff", "expected": "Add backoff.", "notes": "self-correction"}
```

| Field | |
| --- | --- |
| `id` | Unique within the file. |
| `input` | The transcript as speech-to-text wrote it. Copy real ones from the app's Transcriptions history. |
| `expected` | Exactly what you want pasted. Use `\n` for line breaks. |
| `notes` | Optional. Why the case exists. |
| `cleanup` | Optional, default `true`. Set to `false` to skip full deterministic cleanup for this case. |

Name the file after the prompt it targets (`coding.jsonl` tests `Prompts/coding.md`), or pass
`--preset` / `--prompt`.

## Scoring

- **exact**: the output equals the expected text after trimming each line and collapsing
  repeated spaces. Line breaks, capitalisation and punctuation still count.
- **sim**: word-level similarity, 1 − (word edits ÷ the longer text's word count), using the app's
  `WordDiff`.
- **judge** (with `--judge`): PASS/FAIL from the on-device model, which compares the input,
  expected text and actual text. It's the same small model that produced the output, so treat
  its verdict as a hint.

A case **passes** if it's an exact match or the judge says PASS.

## Not covered

- The app skips formatting for dictations shorter than the user's minimum. The evals always format.
- Only the on-device model. Groq and OpenRouter aren't wired in.
- Language is treated as auto-detected (no Parakeet language override).
