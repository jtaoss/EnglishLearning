# Rebuild the reviewed pack and previews

These scripts prepare local content and approval artifacts; they have no Notion write client and never read a system credential.

Required private inputs under `private/p3/`:

- `source/词头候选台账.csv` and original audit manifests, extracted unchanged from the existing audit ZIP.
- `notion-baseline.json`: complete read-only export of the existing 100-word data source. Its `results` retain original Notion IDs; `has_more` must be false. Keep this private because it may contain personal state.
- The official `pets3-2015-official.pdf` and its per-page text-layer export `pets3-2015-text.json`. No OCR is used. The script verifies the 2015 preface and vocabulary appendix location before matching.
- `cmudict.dict`, its license, and `wordnet31.tar.gz` from the sources in the attribution document.

```powershell
python scripts/p3/prepare.py
python scripts/p3/render_preview.py
python scripts/p3/verify_preview.py --batch 200 --snapshot private/p3/notion-baseline.json
```

The default private location can be overridden with `prepare.py --private <directory>`. The renderer currently reads the project-local private output directory.

`editorial.txt` owns the 400 independent common senses/examples. `reading.txt` owns the old 100 words' reading chunks. `phonics.txt` contains word-specific spelling cues; a finite set of reviewed exceptions also lives in `prepare.py`. No general spelling-to-pronunciation engine or audio scraper is used.

Generation stops on duplicate IDs/words, unsupported original head evidence, missing content, inconsistent spelling chunks or unconfirmed CMUdict syllable/stress checks. Case-sensitive pairs are retained. The source ledger is never modified.

Outputs:

- `assets/vocabulary/reviewed500.csv`: portable reviewed content; original 100-word asset remains unchanged.
- `docs/p3/selection-statistics.json`: source hashes, counts and explicit review limits.
- `private/p3/screening5552.csv`: all raw records plus screening decisions; none deleted.
- `private/p3/notion-preview-200.json/.html` and `notion-preview-500.json/.html`: exact changes for approval, with canonical SHA-256.
- `private/p3/preview-200.csv` and `preview-500.csv`: local review/export input.

Only after approval: refetch schema and all rows, verify expected preconditions and unique stable IDs, add approved content fields, create absent IDs, and update only the listed content properties. If a create response is uncertain, query and compare before retrying. Do not regenerate IDs, overwrite personal state, delete remote pages to fix counts, or upload real learning events.

Before execution, rerun `verify_preview.py` against a fresh complete snapshot, adding `--approved-sha <exact-user-approved-hash>`. This is a read-only guard; entering a hash does not itself constitute user authorization and no write tool is invoked by the script. For the 500 batch, the fresh snapshot must contain the accepted 200 words.

`audit_cloud.py --batch 200|500 --snapshot <complete direct rows export> --before <prior snapshot>` compares all 29 content fields and content hashes, stable IDs, page identities and every unrelated/personal property in the prior snapshot. Direct Notion rich text serialization is reduced to its plain text for this comparison. It exports only the actually read cloud content to `private/p3/notion-cloud-<size>.csv`. SQL indexing can lag immediately after writes; never use stale values as acceptance evidence.

Windows snapshot acceptance uses `P3_CLOUD_CSV`, `P3_CLOUD_SIZE`, `P3_CLOUD_REPORT_DIR` and then `P3_CLOUD_COLD_REPORT` with the unified native test entry and `--plain-name "P3 cloud snapshot"`. Supply the actual audited export, never a synthetic fixture. This verifies the existing CSV path, not direct API pagination/incremental sync. An optional separate `P3_LIVE_SIZE` / `P3_LIVE_REPORT_DIR` native test reads a user-saved WinCred token internally; it is skipped until the user configures it. Neither test uploads learning events.

After the two isolated stages pass, `P3_CLOUD_POPULATE_PERSONAL=true` invokes the existing CSV import against the actual Windows database. Back up the actual database first. This path creates no ratings or learning events, preserves existing progress, and checks a second import is unchanged. `finalize_cloud_report.py` publishes counts from the observed private receipts and native reports. `package_release.py` includes the full verified Release bundle and only the audited content CSV, excluding private databases, snapshots and credentials. Close old check processes before validating a rebuilt output directory; use a fresh process for final Release UI acceptance.
