# P6C5a independent targeted verification prompt v1

Independently inspect the original source, all candidate layers/notes, and supplied actual dictionary evidence under V5. Another model may flag a relation; if provided, that is only a hypothesis. First establish source/English semantic scope, then compare the union of source-linked candidates. Do not follow another model's severity automatically.

Return JSON {"records":[...]}, exact input IDs/order. Each has `id`, `scope_checks` (one per original `sid`, `relation` using the six V5 Chinese labels, `reason`, `evidence_ids`), `confirmed_within_supplied_evidence` (array of issues: `severity`, `kind`, `source_ids`, `group_ids`, `evidence_ids`, `reason`, `counterexample`, `repair_suggestion`), `unresolved` (array of concrete uncertain points), `preferences` (array of teaching-only differences), `note`.

No mere frequency/confidence/Chinese substring inference. A dictionary proving a broader meaning does not necessarily prove it is in the source; a subset/example is not automatically a defect if the broad meaning is retained elsewhere with the same POS/source mapping. Properly held source gaps are not passed, but not a misleading core either. Do not demand every original fragment be core. Genuine loss requires concrete source range and a supported omitted use, accounting for all layers. Correct original uncertainty versus generator over-restriction must be distinguished.

This is an independent AI evidence opinion; final adjudication may still remain pending. Output no approved meanings, no IPA, no invented external sources. Return ONLY the audit schema, not copied inputs.
