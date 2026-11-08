# Portable test fixtures

These files let a fresh clone run tests without the original workstation's audit files.

- `vocabulary/verified100_baseline_ids.json`: existing stable Word IDs extracted from the preserved earlier baseline. IDs are not regenerated.
- `notion/verified100_snapshot.json`: existing bundled sample word content, synthetic Notion page IDs, a minimal API schema, and a fixed test timestamp. It contains no real cloud capture, account metadata, credentials, or personal learning history.

Original audits and database backups remain local and are excluded from public Git history. These synthetic fixtures do not establish live Notion or physical-device acceptance.
