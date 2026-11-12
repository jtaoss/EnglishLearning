"""Freeze P6-C inputs; hash previous work without opening any database.

All writes stay under docs/p6/p6c1. Existing snapshots are never overwritten.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/p6/p6c1"
PILOT = ROOT / "docs/p6/p6c/core_meanings_pilot.json"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def paths():
    result = {}
    for directory in ("docs/p6/p6c", "scripts/p6c", "lib/features/core_meanings_pilot"):
        for path in (ROOT / directory).rglob("*"):
            if path.is_file() and "__pycache__" not in path.parts:
                result[path.relative_to(ROOT).as_posix()] = path
    for name in ("docs/p6/P6C_CORE_MEANINGS_PILOT_REPORT.md", "lib/p6c_pilot_main.dart",
                 "test/p6/core_meanings_pilot_test.dart", "test/p6/review_system_test.dart",
                 "docs/p5a/public/formal_learning_vocabulary.csv", "assets/vocabulary/verified100.csv", "assets/vocabulary/reviewed500.csv"):
        result[name] = ROOT / name
    if "APPDATA" in os.environ:
        db = Path(os.environ["APPDATA"]) / "Personal/English Learning/english_learning_v1.sqlite3"
        for suffix in ("", "-wal", "-shm", "-journal"):
            result["%APPDATA%/Personal/English Learning/english_learning_v1.sqlite3" + suffix] = Path(str(db) + suffix)
    return result


def state():
    return {name: {"exists": p.exists(), "sha256": digest(p) if p.exists() else None,
                   "bytes": p.stat().st_size if p.exists() else None, "mtime_ns": p.stat().st_mtime_ns if p.exists() else None}
            for name, p in paths().items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--freeze", action="store_true")
    args = parser.parse_args()
    manifest = OUT / "preservation_manifest.json"
    if args.freeze:
        OUT.mkdir(parents=True, exist_ok=True)
        with manifest.open("x", encoding="utf-8") as f:
            json.dump({"method": "file hashes and metadata only; no SQL connection", "before": state()}, f, indent=2)
            f.write("\n")
        with (OUT / "input_p6c_snapshot.json").open("xb") as f:
            f.write(PILOT.read_bytes())
        print("Frozen P6-C snapshot; previous files protected")
    else:
        old = json.loads(manifest.read_text())["before"]
        if old != state():
            raise SystemExit("Protected P6-C/source/personal path changed; do not repair automatically")
        if digest(OUT / "input_p6c_snapshot.json") != digest(PILOT):
            raise SystemExit("Frozen source differs")
        print(f"PASS: {len(old)} previous/source/personal paths unchanged")


if __name__ == "__main__":
    main()
