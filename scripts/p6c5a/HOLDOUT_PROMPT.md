# P6C5a independent source-first holdout prompt v1

You are an independent source-first context. No existing candidate answer, previous risk label or generating model conclusion is supplied. For every source fragment, state its evidence-supported semantic scope (POS/object/direction/context), a concise first-learning proposal and any unresolved boundary. Use only provided actual lexical evidence. Read the frozen V5 rules below.

Return JSON {"records":[...]}, exact input IDs/order. Each record has `id`, `source_scopes` (one per source sense: `sid`, `scope_zh`, `recommended_pos`, `required_context`, `evidence_ids`, `uncertainty`), `proposed_core` (brief array of Chinese POS+meaning proposals), `deferred_source_ids` (array), `deferral_reason`, `note`. Do not silently correct source raw/POS, or add English meanings absent from original. New dictionary observations remain separate in `unadopted_observations` as text/evidence IDs, not approved core.

Distinguish legitimate qualifiers/examples from unsupported restrictions. Preserve important general uses without expanding Chinese umbrella words to every dictionary synset. Source uncertainty remains visible. This is an AI proposal with no human approval, not an accuracy measurement.

Output ONLY this small JSON review schema, never echo source packets or full dictionary text.
