# Provisional hackathon acceptance checklist

This tracks the September criteria supplied by the organizer while the
October criteria are pending. It distinguishes verified work from publication.

| Criterion | Current evidence |
| --- | --- |
| MoonBit is the main implementation language; moonc >= 0.10.14 | Scanner, CLI, reports and ignore engine are MoonBit; `tools/verify_release.py` checks the compiler version. |
| Public GitHub repository and clear history | [TokeiMBT](https://github.com/aicongli-829/TokeiMBT); source changes and CI checks are committed separately. |
| Clear source structure and working core | Packages are described in [README.md](README.md#architecture); native CLI counts source files by language. |
| Reproducible README | [README.md](README.md) covers installation, build, usage, options and examples. |
| CI checks coverage, build and tests | [GitHub Actions workflow](.github/workflows/ci.yml) runs on Linux and Windows; Linux also reports coverage and dry-runs packaging. |
| Runnable example | `moon run cmd/main -- examples/quickstart`; [example sources](examples/quickstart). |
| Core-path tests | 47 MoonBit tests plus `tools/verify_release.py` integration checks for formats, filters, ignores, file output and saved-report merging. |
| Mooncakes publication | **Pending.** Maintainer must register/log in, align the module owner with that account, and run `moon publish`. CI runs `moon publish --dry-run`. |
| OSI license and upstream attribution | [Apache-2.0 LICENSE](LICENSE); [Tokei language-table attribution](vendor/tokei-v15.0.0/README.md). |

The October-specific criteria should be checked against this list when
published. The 333 imported language definitions are not a claim that every
Tokei feature or grammar edge case has been verified; see
[PORTING_STATUS.md](PORTING_STATUS.md).
