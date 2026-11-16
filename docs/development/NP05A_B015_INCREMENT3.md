# B-015 / NP05A — reason-coded material waste observations

2026-11-16. Own branch `build/codex-np05a-sweets`, Draft PR #112. Latest trunk incorporated: `fe1c6b6`. Reservation used: **0502**, inside 0500–0599. Migrations 0500 and 0501 remain unchanged.

## Delivered behavior

`0502_np05a_material_waste.up.sql` and matching rollback add an immutable manufacturing observation table, not another stock/money/audit ledger. Every observation links a recorded batch, recipe component, canonical item ID, declared recipe UOM, actual consumption lot reference, quantity, reason, note, actor and canonical Audit event. Direct API table/sequence mutation is not granted; RLS is enabled; definer functions pin search_path. Immutable update/delete/truncate guards preserve evidence.

New versioned RPCs:

- `mfg_record_material_waste_v1(business,site,batch,line,quantity,reason,lot_ref,note,key)`: canonical scoped Owner authorization, command and batch locks, fresh Auth/Control, then actor/payload-bound replay. It requires recorded output and an exact match to that component's recorded lot reference. Six-decimal quantities must be positive and finite. Cumulative observed waste cannot exceed recorded consumption or the Owner's configured percentage.
- `mfg_material_waste_report_v1(business,site,batch)`: scoped, read-only per-line consumption/waste/unclassified consumption, planning waste estimate, reason codes, policy limit and immutable history. It never adds unlike UOMs into a total or certifies unclassified consumption as good use.

The canonical Control feature **mfg.material_waste** defaults to enabled, zero approval stages, 30% maximum cumulative waste per material and configurable CSV reason codes `PROCESS_LOSS,QUALITY_REJECT,SPILLAGE,PACKAGING_DAMAGE`. These are editable canonical settings, not independent grants/policies. The writer is registered `enforced`, with `tests/np05a/material-waste-e2e.sql` as CI-run disabled-feature evidence. Configured nonzero stages refuse with `NOT_CONNECTED:APPROVAL_COMPLETION`. A one-use canonical exception is consumed once. Managers/operators/auditors remain denied until canonical manufacturing-specific actions are supplied by NP01.

## No double posting

A material waste observation classifies part of an already-recorded consumption quantity. It does **not** issue another stock movement, add to planned/recognized costs, reduce finished output again, create COGS/valuation or post a journal. It does not validate a physical lot or convert units. Those canonical receiver services remain NOT_CONNECTED.

For example: consumed milk 10 kg; observed waste 1.5 kg; remaining 8.5 kg is **unclassified consumption**, not automatically good output. Packaging waste stays in pieces, and output process loss/rejection/rework stays in the recipe yield UOM. They are different measurements, not amounts to add together.

The existing private handoff builder now includes `material_waste_events` with observation IDs and canonical Audit references. New source snapshots include new observations and get a new fingerprint; old idempotent receipts retain their original snapshot. Stock/Finance flags remain false and recognized value/journal entries remain NULL. A future connected receiver must require an explicit correction for an already-posted source rather than repost a changed snapshot. No receiver endpoint is invented.

Rollback 0502 restores the exact 0501 handoff definition only on unused history. It refuses observations, this feature's Control history/overrides, or new handoff snapshots containing `material_waste_events`.

## UI and retry protection

The existing Bangla/English development workbench has **উপকরণের অপচয় / Material waste** on recorded batches and the yield report. It shows each component's recorded consumption, waste, unclassified remainder, lot reference and Audit-linked history, plus a normal form for quantity/reason/note. It states that there is no additional Stock issue or cost and that UOM/lot validation is pending. Existing Central shell/navigation is untouched.

If the server commits an observation but its response is lost, the form keeps the original request key for unchanged data. It blocks changed data while that result is uncertain and asks the user to refresh/inspect history. Successful writes followed by a report-refresh failure still show the saved Audit receipt. Context disposal invalidates in-flight results.

## Actual verification

Local disposable PostgreSQL 17 with synthetic subject claims; no hosted identities or signed GoTrue certification:

- **30 migrations up → full down → up PASS**, including upstream 0150 Master tables; static migration contract 6/6 PASS, signed-scope client tests 5/5 PASS.
- Existing manufacturing, material/handoff, canonical Control and NP02 Master-table suites PASS. Registry/evidence PASS: 29 callable mutations total, 11 enforced / 7 exempt / 11 upstream pending; NP05A now contributes 8 enforced writers.
- New `tests/np05a/material-waste-e2e.sql` PASS: actual unmodified Master adapter refuses first; only fixture recipe approval/release uses the existing explicitly test-only Master adapter. Tests include custom reason policy, exact threshold, cumulative bounds, packaging vs kg, NaN/Infinity/zero/precision, lot/line/note errors, replay conflict, disabled read/write including replay, one-use exception, nonzero-stage approval refusal, scoped role negatives, canonical Audit linkage, immutability and zero stock mutation. Source fingerprints change only for new snapshots; prior snapshots and planning cost remain unchanged.
- Existing simultaneous replay and lock-wait suites PASS.
- New `tests/np05a/waste-race.sh` PASS: simultaneous same-key calls create one event; of two different-key calls exceeding the cumulative limit, only one succeeds. Real batch-row waits observed through pg_stat_activity: Owner disable or immediate role revocation blocks the waiting writer without a receipt. Rollback refuses recorded history.
- **Chromium 48 checks PASS at 390/1440**: existing features plus real waste entry, scoped history, no overflow, and transport-loss retry. Browser test lets real SQL commit, deliberately loses its HTTP response, blocks a changed retry, retries unchanged data with the same key and proves exactly one observation in history. This is transport fault injection, not a mocked production write.

Screenshots: `np05a-evidence/waste-390.png`, `waste-1440.png`; results `increment3-results.json`. CI uploads its own exact-HEAD evidence. Exact-head CI URLs/results are maintained in Draft PR #112 and B-015.

## Dependencies and next safe integration

B-011 now has real **0150 Master tables**, extending canonical items in place. At the checked trunk `fe1c6b6`, 0151 Master conversion/validation RPCs are still absent; table existence is not a connected port. B-012 Stock remains planned. NP06 PR #108 was inspected at `88a2964`; the verified manufacturing valuation receiver is still absent. Approval completion, manufacturing Auth actions and Central-shell entry remain other owners' work. Existing integration requests in the original handoff remain valid; no shared implementation is replaced.

Status: **CODED / TESTED isolated manufacturing increment; full S6 BLOCKED / NOT READY_FOR_INTEGRATION / NOT VERIFIED_COMPLETE**. Next: bind verified NP02 conversion/item status services when their owner publishes them, then Approval/Stock/Money contracts. Substitution/returns, co-products/over-yield, routing/capacity/WIP/subcontract/downtime and full signed 16-persona certification remain unfinished. Do not apply 0500–0502 to persistent databases ahead of upstream blocks.

No hosted Supabase apply, staging seed/users, Cloudflare deployment, unauthorized merge or IMG-ERP-SG access. Decision Book NOT WRITTEN: this increment implements existing scope; no new Owner policy decision or cross-owner write is made.

Owner QA: ব্যাচ → **উপকরণের অপচয়** → উপকরণ, পরিমাণ, কারণ ও ব্যাখ্যা দিন → Audit-সহ ইতিহাস দেখুন। এটি standalone development QA, integrated ERP বা live factory posting নয়।
