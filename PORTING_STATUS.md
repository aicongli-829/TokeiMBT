# Tokei porting status

This file records verified behavior and the next compatibility milestones.

The compatibility target is official Tokei v15.0.0. Its 333 imported language
definitions are not custom additions. Tokei v12.1.2 is only a runnable
comparison baseline: it has 226 definitions and omits MoonBit, so pruning to
that older table would remove a core reason for this port.

## Verified on Windows/native

- `moon test --target native`: 47 passed (2026-10-27, from an ASCII-path
  copy of the checkout on Windows).
- `moon check --target native --deny-warn` and `moon build --target native`
  pass.
- `moon build --target native` produced a working Windows executable. An
  optimized native release build generated a roughly 3.8 MB C translation
  unit and did not finish during this session; release performance remains
  unverified.
- A single `.mbt` file can be scanned by the CLI.
- `--files` includes line, code, comment and blank counts.
- The language table contains 333 imported definitions. Basic line/block
  comment fixtures now run for all definitions that declare those delimiters.
- JSON and YAML include `Total`, file reports and nested child-language
  statistics. A Python/Markdown Jupyter fixture and five plain-language
  fixtures match the isolated official Tokei 12.1.2 binary in complete JSON
  structure after normalizing path separators. Two-file notebook aggregation
  and kernel metadata fallback/precedence were compared separately.
- The reproducible matrix checks 1,341 files across 201 definitions identical
  in the v12.1.2 and v15.0.0 language tables. All match official v12.1.2
  per-file language, code, comment and blank counts. Cases include simple
  code, line and block comments, nested blocks, comment text inside strings,
  multiline quotes, CRLF, UTF-8 BOM, shebangs, and no final newline. The comparison does not
  cover every syntax rule or every imported language.
- The complete JSON report for the generated 1,341-file directory also matches
  official v12.1.2 after normalizing path separators and sorting report lists.
- The 333 imported definitions match a pinned Tokei v15.0.0
  `languages.json` snapshot after formatter normalization.
- Local `.gitignore`, `.ignore`, and `.tokeignore` rules are loaded, with
  independent switches for VCS and dot ignore files.
- Basic terminal tables, wider columns, grouped number styles, and Jupyter
  embedded rows and per-file child details match eight official v12.1.2 output
  cases after normalizing Windows path separators. `-C` suppresses aggregate
  embedded rows as upstream does, while `-f -C` retains the per-file details.
- `--input <file>` reads official or TokeiMBT JSON reports, preserving file and
  child-language data, and merges their counts with a fresh scan.
- The release gate also exercises five-language sample output, type filters,
  `--files`, JSON/CSV/YAML, `--output-file`, and ignore/exclude behavior.
- Native coverage instrumentation reports 1,124 / 1,621 covered points on
  2026-10-27. The `cmd/main` entry point is exercised by CLI integration
  checks but is not instrumented by the unit-test coverage run.

## Next compatibility milestones

1. Expand differential fixtures to every claimed language and richer syntax,
   including raw/verbatim strings, nested edge cases and embedded
   languages. The data snapshot is pinned at v15.0.0; a v15 executable is still
   needed for a same-version differential run.
2. Verify the complete ignore behavior: parent and nested `.gitignore`,
   negation, re-inclusion, escaped spaces, anchored patterns, and VCS/global
   ignore rules. Keep the traversal tests independent from parser tests.
3. Bring more complex `--files` embedded-language cases and CBOR serialization
   into alignment with upstream output. Basic Jupyter code and Markdown child
   reports now include per-file details; other embedded formats remain.
4. Finish the upstream CLI option and error/exit-code compatibility matrix.
   `--input stdin`, configuration files, and several reporting options remain.
5. Test large repositories, symlinks, duplicate roots, unreadable files,
   binary files, and performance. File-name and extension lookup now use
   indexes; matcher construction and shebang lookup still need profiling.
6. Run the matrix in cross-platform CI and benchmark performance before
   claiming feature or speed parity. The local matrix writes an ignored
   `.scratch/matrix-report.json`; its pinned reference data is vendored.

Source line accounting on 2026-10-24 (excluding dependencies and build
outputs): approximately 2,730 handwritten non-test MoonBit lines, 531 test
lines, and 5,063 generated language-data lines. Generated definitions should not be
represented as independently implemented language parsers.
