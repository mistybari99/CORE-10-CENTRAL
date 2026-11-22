# B-015 / NP05A — material planning and handoff increment

2026-11-16. Own branch `build/codex-np05a-sweets`, Draft PR #112. Latest upstream incorporated: `54607f1` (B-009 drift gate and B-011 Master contract). Existing migration 0500 is unchanged. New migration: **0501_np05a_material_handoff.up.sql / .down.sql**.

## What works without a Master/Stock/Money stand-in

`mfg_material_requirements_v1(business,site,recipe,multiplier)` is an Owner/site-scoped, read-only RPC against real canonical item IDs and the versioned recipe. It works for drafts as a non-posting plan. It reports each ingredient/packaging component separately, scaled gross input, expected waste share and usable amount in that line's UOM, output quantity in the recipe UOM, manual-rate line costs and scaled overhead. Quantities are validated to six decimals before multiplication can be used; expected waste is display-rounded to six decimals. Costs never become recognized valuation/COGS.

Unavailable stock, shortages, allocation lots and base-UOM quantities remain **NULL**, with `NOT_CONNECTED` indicators. Never substitute zero stock for missing Stock data, never sum kg with pieces, and never estimate kg→pieces conversion. This is material requirements planning, not stock reservation or a procurement order.

The read feature `mfg.material_requirements` appears in the canonical Control catalog. Its read-only RPC uses the authoritative scoped Control resolver, is STABLE and does not consume exceptions or create audit events. No additional state-changing API/registry exemption was introduced.

## Source handoff contract (proposal, no connected receiver)

Existing `mfg_request_handoff_v1` now stores/returns a deterministic `source_envelope` inside its existing immutable command receipt and canonical Audit result. No request table, stock movement, balance or finance journal is added.

Envelope contract identifier: `np05a.manufacturing_handoff.v1`:

- `contract_status=PROPOSED_NOT_CONNECTED`; no receiver endpoint/signature is invented.
- `scope`: canonical tenant/business/site; `source`: batch/status, recipe ID/version, location and original recipe/batch Audit IDs.
- Ingredients: each planned BOM/packaging quantity and UOM, stable source line number; unallocated lot and base quantity are NULL.
- Finished goods: recorded **good output only**, finished item/UOM and output lot reference. Rejected, rework and process loss remain observations; none silently turns into a stock receipt/journal.
- Finance: observed production source and manual planning cost, with `recognized_value=NULL` and `journal_entries=NULL`.
- `source_fingerprint`: PostgreSQL SHA-256 of the normalized JSONB body excluding this field. It is an opaque provenance identifier, not an authorization token/signature. A receiver must validate scope/approvals/source and enforce exactly-once semantic source `(business, batch, kind)` independently of request-key retries. Use PostgreSQL normalization if recomputing; JavaScript JSON serialization is not the same canonical representation.
- Flags stay `stock_issued=false`, `stock_received=false`, `financial_posted=false`; Master UOM and lot validation remain NOT_CONNECTED. Replaying a receipt returns its original envelope even after subsequent batch progress. New source requests reflect the current batch snapshot, with original Audit IDs (earlier handoff requests do not recursively enter the source fingerprint).

The materials-report switch controls that report, not the separate handoff feature. Handoff's private source builder reuses the calculation helper, so disabling a read report is not an undocumented policy for Stock/Finance.

## Lock-wait authorization correction

0501 replaces the seven existing mutation definitions without changing their signatures or receipt format. Lock order is command-key advisory lock, then recipe-version/batch/recipe lock where applicable. After blocking locks complete, canonical `_mfg_scope_v1` is called again and the exact registered `control_check_v1` runs **once** before replay return or mutation. No new grants or policy engine.

The initial regression caught a replay conflict being returned before disabled-feature denial. A private lock-only helper now acquires the command lock first; payload replay validation occurs after fresh Auth/Control. The original disabled-feature assertions remain unchanged and pass.

Canonical Control resolves effective dates using `statement_timestamp()`. When a new setting/schedule becomes effective during a blocked statement, rechecking against that earlier time can miss it. The private freshness guard detects only this timing mismatch in canonical Control history and raises **MFG_CONTROL_CHANGED_RETRY**. It does not resolve or override policy. A fresh request uses the new canonical setting and returns CONTROL_DISABLED when switched off. Existing one-time exceptions still pass through the canonical check exactly once; no double consumption.

## Verification and evidence

Local disposable PostgreSQL 17: all checks below PASS. Canonical Auth/Control/Audit predicates; synthetic subject claims only:

- Full migration up → down → up: **28 migrations**, idempotent reapply.
- Existing manufacturing lifecycle/security negatives unchanged: regression proof.
- New `tests/np05a/material-handoff-e2e.sql`: draft requirements **before** the test-only Master fixture; 20 kg vs 20 packaging pieces kept separate, expected waste 0.4 kg, total planning cost 2200 BDT; unknown stock/shortage stays NULL; scope/precision/disabled report/private-helper negatives. Handoff fingerprints, replay snapshots, recipe-version/Audit links, no valuation/GL, source lot, no waste-as-receipt, single-use exception and zero Stock mutation. Only the approved/released domain lifecycle uses the existing explicitly test-only Master fixture, inside a rolled-back transaction.
- Existing simultaneous replay test and history-protected 0500 rollback.
- New `tests/np05a/lock-wait.sh`: real sessions, waits observed via `pg_stat_activity`, not guessed timing. Owner disables handoff while its command lock is blocked; role revoked while batch row lock is blocked; Owner disables recipe while version allocation is blocked. All refuse without receipts. A successful source handoff then proves 0501 rollback refuses its new history.
- Static migration checks and signed-scope client tests; canonical Control registry/evidence.
- **32 browser checks PASS** at 390/1440: existing flow plus draft requirements, explicit unknown availability, source fingerprint inspection, no overflow, Bengali/English and context disposal. Genuine screenshots committed to `np05a-evidence/`; CI saves its own screenshots at the exact HEAD.

CI execution/results are recorded in Draft PR #112 and B-015 at the exact pushed SHA. Initial harness retries included a reused disposable seed collision and a rollback-negative fixture without any new history; both were corrected using a clean disposable database and a successful source receipt, without weakening production checks.

## Integration status / next dependency

The live Board and trunk were checked before work. B-011's accepted contract `docs/coordination/NP02_B011_MASTER_DATA_CONTRACT.md` describes planned UOM/item services but provides no implemented conversion signature yet. B-012 remains planned; NP06 PR #108 is open and does not supply a verified production-source valuation adapter. Manufacturing Auth actions and approval-completion routing remain other owners' work. Existing requested contracts in `NP05A_B015_MANUFACTURING.md` still apply; no shared-source change or hosted operation was performed.

**CODED / TESTED isolated increment. Full S6 remains BLOCKED / NOT READY_FOR_INTEGRATION / NOT VERIFIED_COMPLETE.** Next safe integration: bind the implemented, verified NP02 UOM/item port and manufacturing Auth actions when those owners publish them, then Approval/Stock and Money receiver contracts. Do not apply 0500/0501 ahead of required lower blocks. Substitution/returns, co-products, over-yield, routing/capacity/WIP/subcontract/downtime, signed 16-persona certification and Central-shell entry remain unfinished.

## Owner inspection (development QA)

রেসিপি → **উপকরণ চাহিদা** → গুণক দিন → প্রতিটি উপকরণ/প্যাকেট ও প্রত্যাশিত অপচয় দেখুন। মজুত/ঘাটতি অজানা থাকলে সেটাই দেখাবে। ব্যাচ → **সংযোগ পরীক্ষা** → প্রস্তুত সূত্রে পরিমাণ, লট, Audit ও fingerprint দেখুন। এটি stock/হিসাব পোস্টের সফলতা নয়।

No hosted Supabase migration, staging seed/users, Cloudflare deployment, unauthorized merge or IMG-ERP-SG access. Own branch, disposable testing, commits/push and Draft PR/own Board fields only.
