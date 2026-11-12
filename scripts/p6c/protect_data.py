"""Hash known source files and the known personal database path; never open SQL.

Only --snapshot writes a pilot manifest. --check never writes protected files.
No directory search, backup restore, process launch, or repair is performed.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/p6/p6c/data_protection.json"
SOURCES = ["docs/p5a/public/formal_learning_vocabulary.csv", "assets/vocabulary/verified100.csv", "assets/vocabulary/reviewed500.csv"]
PERSONAL = "%APPDATA%/Personal/English Learning/english_learning_v1.sqlite3"


def state():
    paths = {name: ROOT / name for name in SOURCES}
    if "APPDATA" in os.environ:
        db = Path(os.environ["APPDATA"]) / "Personal/English Learning/english_learning_v1.sqlite3"
        for suffix in ("", "-wal", "-shm", "-journal"):
            paths[PERSONAL + suffix] = Path(str(db) + suffix)
    return {name: {"exists": p.exists(), "sha256": hashlib.sha256(p.read_bytes()).hexdigest() if p.exists() else None,
                   "bytes": p.stat().st_size if p.exists() else None,
                   "mtime_ns": p.stat().st_mtime_ns if p.exists() else None} for name, p in paths.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot", action="store_true")
    args = parser.parse_args()
    current = state()
    if args.snapshot:
        with OUT.open("x", encoding="utf-8") as stream:
            json.dump({"method": "file-byte hashes + metadata only; no SQLite connection", "scope_limitation": "Only the explicitly known personal path and its sidecars; no disk/path discovery", "before": current}, stream, indent=2)
            stream.write("\n")
        print("Created exclusive protection baseline")
        return
    baseline = json.loads(OUT.read_text(encoding="utf-8"))["before"]
    if baseline != current:
        raise SystemExit("Protected source or known personal DB changed; investigate, do not restore automatically")
    print(f"PASS: {len(current)} protected paths unchanged (including missing sidecars)")


if __name__ == "__main__":
    main()
