# P6C5a scope-audit prompt v1

Read every original source fragment first, in its actual source POS/context. Compare with the UNION of ALL linked candidate groups (core/extended/other), including their usage notes and precise dictionary evidence. Evaluate the complete V5 rules below. You audit existing data, not generate new meanings. Source-held fragments remain unresolved, not passed. Do not silently convert source-POS null into a known source label. Group POS is a recommendation only.

Output JSON {"records":[...]}, exactly the input IDs/order. Each record MUST contain:

`id`; `mappings`: exactly one entry per original source_sense_id; `word_status`: complete/partial/uncertain; `core_status`: adequate/justified_deferred/pending; `issues`: array; `note`: concrete per-word summary.

Each mapping has `sid`, `source_scope` (brief Chinese), `relation` (one of 语义等价/合理概括/范围收窄/范围扩大/语义不匹配/无法确定), `reason`, `evidence_ids` (only actual supplied IDs, may be [] when insufficient), `context` (required_from_source/required_for_lexical_use/example_not_exclusive/unlicensed_limit/uncertain/none), `residual_scope` (missing/extra range or empty string), `counterexample` (brief contrasting supported USE, not invented sentence/frequency), `counterexample_evidence_ids` (provided IDs, or []), `risk` (none/pending/suspected_Major/suspected_Minor). Do not return the whole input, candidate or English evidence list.

Each issue has `severity` Critical/Major/Minor/Info, `kind`, `source_ids`, `group_ids`, `evidence_ids`, `reason`, `repair_suggestion`. Issues are AI REVIEW PROPOSALS, not human-approved or automatically confirmed errors.

DO NOT infer coverage from Chinese string containment. DO NOT infer correct prioritization from frequency of the whole headword, WordNet order, or confidence. Do not insist every dictionary use belongs in source/core. A correctly qualified child use can be valid, but if the original supported general range is left without any retained branch/explicit pending remainder, flag the residual scope. Check object vs cause/state, activity vs people/artifact, concrete vs abstract, and context/domain boundaries. A word's broader lexical uses absent from original belong outside source-derived layers. A source translation too broad for the English word is SOURCE UNCERTAINTY, not automatically a generator Major. Examples in a note are not automatically exclusive limits.

Returning a relation is a judgment, NOT a formal proof. Use 无法确定 and explicit pending where evidence is insufficient. A known use retained in extended is not omitted from the word; first-screen deferral is a separate teaching judgment. Absence of a corpus does not prove a meaning rare. A lexical/source conflict remains pending even if the model recognizes a likely translation.

After the V5 rules, RETURN ONLY THE SMALL AUDIT JSON SCHEMA ABOVE. Never echo the input. Do not output any human_approved=true or newly adopted meanings.
