# NP01 B-008 — Legacy site crosswalk ambiguity guard (2026-11-16)

Scope: `build/chatgpt-np01` / Draft PR #107. Advisory preflight only, incremental CHG-010/CHG-014 negative-case hardening, NOT GOV-001 or business-setup certification.

## Finding and correction
Previously `legacyImportPreview()` flagged a duplicate source only after its first occurrence and allowed multiple distinct legacy sources to look mapped to the same target site. That ambiguity cannot establish custody or historical identity safely.

The entire batch is now normalized before classification. Every repeated legacy source ID is flagged `BLOCKED_DUPLICATE_SOURCE`; all distinct sources competing for one known site ID in the selected business are flagged `BLOCKED_DUPLICATE_TARGET`. Foreign-business rows, unknown target IDs and unmapped rows remain fail-closed. Candidate classification is order-independent and never inferred from labels/names.

## Tests and remaining gates
`tests/setup001/setup-profile-engine.test.cjs` covers reversed order, two competing sources, trimmed duplicate IDs, foreign business and no-write guarantees. Verify in NP01 existing exact-head CI.

No migration number reserved or applied. No signed setup activation, site/custody location conversion, legacy IMG-ERP-SG import, tenant creation, role grants, or hosted writes. `can_import:false` and `write_count:0` remain unconditional.

B-010 Owner Control by Claude, B-018 hosted signed GoTrue, GOV-001 remaining subparts, and the D051 release fence remain OPEN. Coordinate through the shared board before any integration.
