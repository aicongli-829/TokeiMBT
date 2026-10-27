#!/usr/bin/env python3
"""Run the local checks needed before publishing this Tokei port.

Usage:
    python tools/verify_release.py
    python tools/verify_release.py --upstream path/to/tokei-12.1.2.exe

The optional upstream binary enables differential checks; it is never
downloaded or included in the repository.
"""

import argparse
import json
import pathlib
import re
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "vendor/tokei-v15.0.0/languages.json"
GENERATED = ROOT / "lang/data.mbt"
MIN_MOONC_VERSION = (0, 10, 14)


def run(*args: str) -> str:
    result = subprocess.run(
        list(map(str, args)),
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if result.returncode:
        print(result.stdout, file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        raise SystemExit(result.returncode)
    return result.stdout


def verify_language_table() -> None:
    official = json.loads(SNAPSHOT.read_text(encoding="utf-8"))["languages"]
    literals = re.findall(r'^\s+key: ("(?:\\.|[^"\\])*")',
                          GENERATED.read_text(encoding="utf-8"), re.MULTILINE)
    generated = [json.loads(literal) for literal in literals]
    if len(generated) != len(official) or set(generated) != set(official):
        raise SystemExit("Generated language keys differ from the pinned official v15 table")
    if "MoonBit" not in official:
        raise SystemExit("MoonBit is missing from the pinned official table")
    print(f"language definitions: {len(official)} official v15 keys match generated MoonBit data")


def verify_toolchain() -> None:
    output = run("moon", "version", "--all")
    match = re.search(r"\bmoonc v(\d+)\.(\d+)\.(\d+)\b", output)
    if not match:
        raise SystemExit("Could not determine moonc version from moon version --all")
    version = tuple(map(int, match.groups()))
    if version < MIN_MOONC_VERSION:
        raise SystemExit(
            f"moonc {'.'.join(map(str, version))} is below required 0.10.14"
        )
    print(f"moonc version: {'.'.join(map(str, version))} (minimum 0.10.14)")


def binary_path() -> pathlib.Path:
    path = ROOT / "_build/native/debug/build/cmd/main/main"
    if sys.platform == "win32":
        path = path.with_suffix(".exe")
    if not path.is_file():
        raise SystemExit(f"Built CLI not found: {path}")
    return path


def run_cli(*args: str) -> str:
    """Launch the CLI through MoonBit across native platforms."""
    return run("moon", "run", "cmd/main", "--", *args)


def verify_cli(expected_languages: int) -> None:
    listing = run_cli("--languages")
    if not listing.startswith(f"Languages: {expected_languages}\n"):
        raise SystemExit("CLI reports the wrong language count")
    if "  MoonBit (mbt, mbti)" not in listing:
        raise SystemExit("CLI does not advertise MoonBit extensions")
    report = json.loads(run_cli("-o", "json", "counter/counter.mbt"))
    moonbit = report.get("MoonBit")
    if not moonbit or moonbit["code"] <= 0 or len(moonbit["reports"]) != 1:
        raise SystemExit("CLI could not count its own MoonBit source file")
    if report["Total"]["code"] != moonbit["code"]:
        raise SystemExit("Total and MoonBit counts disagree")
    fixture = "tests/fixtures/plain"
    multi = json.loads(run_cli("-o", "json", fixture))
    if multi["Total"]["code"] != 23 or set(multi) != {
        "C", "Go", "JavaScript", "Python", "Rust", "Total"
    }:
        raise SystemExit("CLI sample does not match the documented five-language report")
    selected = json.loads(run_cli("-o", "json", "-t", "python,rust", fixture))
    if set(selected) != {"Python", "Rust", "Total"} or selected["Total"]["code"] != 11:
        raise SystemExit("CLI language filter did not keep only Python and Rust")
    if "raw.rs" not in run_cli("--files", fixture):
        raise SystemExit("CLI per-file table omitted the Rust sample")
    if not run_cli("-o", "csv", fixture).startswith(
        "Language,Files,Lines,Code,Comments,Blanks\n"
    ):
        raise SystemExit("CLI CSV header is missing")
    if not run_cli("-o", "yaml", fixture).startswith("---\n"):
        raise SystemExit("CLI YAML document marker is missing")
    with tempfile.TemporaryDirectory() as tmp:
        saved = pathlib.Path(tmp) / "previous.json"
        saved.write_text(json.dumps(report), encoding="utf-8")
        merged = json.loads(run_cli("--input", saved, "-o", "json",
                                    "counter/counter.mbt"))
        if merged["Total"]["code"] != report["Total"]["code"] * 2:
            raise SystemExit("CLI could not merge a saved report with a fresh scan")
        if len(merged["MoonBit"]["reports"]) != 2:
            raise SystemExit("Saved per-file reports were not preserved")
        exported = pathlib.Path(tmp) / "export.json"
        run_cli("--output-file", exported, "-o", "json", fixture)
        if json.loads(exported.read_text(encoding="utf-8")) != multi:
            raise SystemExit("CLI --output-file differs from stdout JSON")
        scan = pathlib.Path(tmp) / "scan"
        scan.mkdir()
        (scan / "keep.rs").write_text("fn keep() {}\n", encoding="utf-8")
        (scan / "skip.rs").write_text("fn skip() {}\n", encoding="utf-8")
        (scan / ".gitignore").write_text("skip.rs\n", encoding="utf-8")
        ignored = json.loads(run_cli("-o", "json", scan))
        unignored = json.loads(run_cli("-o", "json", "--no-ignore-vcs", scan))
        excluded = json.loads(run_cli("-o", "json", "--no-ignore-vcs",
                                      "-e", "skip.rs", scan))
        if (len(ignored["Rust"]["reports"]), len(unignored["Rust"]["reports"]),
                len(excluded["Rust"]["reports"])) != (1, 2, 1):
            raise SystemExit("CLI ignore and explicit exclude behavior disagrees")
    print("CLI integration: sample, filters, formats, files, ignore and JSON merge pass")


def verify_terminal_parity(binary: pathlib.Path, upstream: pathlib.Path) -> None:
    cases = [
        (ROOT / "tests/fixtures/plain", []),
        (ROOT / "tests/fixtures/plain", ["-c", "100"]),
        (ROOT / "tests/fixtures/embedded", []),
        (ROOT / "tests/fixtures/embedded", ["-C"]),
    ]
    with tempfile.TemporaryDirectory() as tmp:
        large = pathlib.Path(tmp) / "large.rs"
        large.write_text("fn main() {}\n" * 1234, encoding="utf-8")
        cases.append((large, ["-n", "commas"]))
        for fixture, flags in cases:
            official = run(upstream, fixture, *flags)
            port = run(binary, fixture, *flags)
            if official != port:
                raise SystemExit(
                    f"Terminal output differs from upstream for {fixture} {flags}"
                )
    for fixture, flags in [
        (pathlib.Path("tests/fixtures/embedded/sample.ipynb"), ["-f"]),
        (pathlib.Path("tests/fixtures/embedded/sample.ipynb"), ["-f", "-C"]),
        (pathlib.Path("tests/fixtures/embedded/sample.ipynb"), ["-f", "-c", "110"]),
    ]:
        official = run(upstream, fixture, *flags).replace("\\", "/")
        port = run(binary, fixture, *flags).replace("\\", "/")
        if official != port:
            raise SystemExit(
                f"Embedded file table differs from upstream for {fixture} {flags}"
            )
    print("official terminal comparison: eight table cases match after path normalization")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", type=pathlib.Path,
                        help="optional official Tokei 12.1.2 executable")
    args = parser.parse_args()
    verify_toolchain()
    verify_language_table()
    run("moon", "check", "--target", "native", "--deny-warn")
    print("moon check: pass")
    tests = run("moon", "test", "--target", "native")
    print(tests.strip().splitlines()[-1])
    run("moon", "build", "--target", "native")
    print("moon build: pass")
    verify_cli(333)
    if args.upstream:
        binary = binary_path()
        upstream = args.upstream.resolve()
        matrix_result = run(sys.executable, ROOT / "tools/diff_matrix.py",
                            "--upstream", upstream, "--port", binary)
        print(matrix_result.strip().split(" report=", 1)[0])
        matrices = sorted((ROOT / ".scratch").glob("matrix-*"),
                          key=lambda path: path.stat().st_mtime)
        if not matrices:
            raise SystemExit("Differential matrix did not create its fixture directory")
        run(sys.executable, ROOT / "tools/compare_structured.py", "--upstream",
            upstream, "--port", binary, matrices[-1],
            ROOT / "tests/fixtures/embedded")
        print("official v12.1.2 comparison: pass")
        verify_terminal_parity(binary, upstream)
    print("release checks: pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
