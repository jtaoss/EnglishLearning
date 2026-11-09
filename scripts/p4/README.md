# P4: existing 500-word learning acceptance

No vocabulary expansion, OCR, Android builds or event upload is performed.

- `audit.py` reads the unchanged reviewed CSV and existing private source/reference exports. It produces full 500-row checks, review flags, source-based before/after values and six-file attribution/hash results under docs/p4. No cloud write client or credential access exists in this script.
- Native specs are registered by the unified integration_test/app_acceptance_test.dart. Use `--plain-name "P4 actual learning"` and the usual Windows config.
- Warm learning: `P4_LEARNING=true`, `P4_REPORT_DIR=<absolute local directory>`. Creates a separate temporary SQLite, blocks Dart HTTP, exercises 34 production word cards and actual native playback. Windows needs an installed Microsoft en-US Desktop voice. Never substitute the formal DB path.
- Cold process: `P4_COLD_REPORT=<absolute learning.json>`. Confirms independent PID, all saved grades/dates/source types and full 500 content.
- Real API: `P4_NOTION_LIVE=true` plus the warm report directory. Reads the user-saved WinCred token internally; full/repeat/incremental reads preserve the 34 isolated records. No token test arguments or files.
- Formal cache: after a safe SQLite backup, `P4_NOTION_PERSONAL=true` and the report directory. Only content reads/syncs; compares all four existing personal tables and never creates synthetic learning grades.
- `write_reports.py` requires actual PASS receipts and test/build logs; it publishes six reports and compact statistics, excluding private DB paths and credentials.
- `package_release.py` packages the full Release bundle, the reviewed content CSV and report index. Never package private/, local databases or WinCred content.

Native playback completion and reference checks are not a human accent certification. Keep unresolved review flags and the original content; do not silently overwrite meanings or mark user confirmation complete.
