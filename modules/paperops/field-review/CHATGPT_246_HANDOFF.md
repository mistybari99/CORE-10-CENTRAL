# CORE-10-CENTRAL — CHATGPT LANE B: ORIGINAL 246 SOURCE CONTROLS, CORRECTION & INTEGRATION BUILD

**Owner delegation: 23 November 2026. New ChatGPT conversation. This is a BUILD assignment (code + negative tests + isolated Draft PR) and must not become an endless review-only exercise.**

## 0. Locked 246-field ownership

Repository `mistybari99/CORE-10-CENTRAL`; canonical integration trunk `ccr-15ed11dd-n3hw5h`. Parent PaperOps Draft PR **#132**, source branch `build/paperops-foundation-20261122`. This is a continuation of source recheck and prototype builds, not a restart of the ERP.

**READ FIRST in this exact order:**
1. `docs/development/AGENT_HANDOVER_CURRENT.md` all relevant §§1–4, 7 and safety rules; `docs/development/CLAUDE_TRUNK_HANDOFF.md` top, `docs/coordination/WORK_SPLIT_AND_PROTOCOL.md` and `docs/coordination/MIGRATION_RESERVATIONS.json`.
2. `modules/paperops/field-review/ownership-246-1000.json` (**MACHINE-LOCKED FIELD ASSIGNMENT**), `modules/paperops/tests/ownership-split-246-1000.test.cjs`. Your IDs are **exactly** concatenation of `lane_B_chatgpt.critical_86_keys`, `mapped_150_keys`, `reserved_next_10_keys` = **246 distinct IDs**. ALL other **1,000 belong exclusively to Codex**.
3. Preserved original source `legacy/islamia-erp/forms.js` and any other old preserved source files needed to understand `O()/n()` helper or warnings, **READ ONLY as text, never execute**, never access original Supabase projects.
4. `modules/paperops/legacy-field-index.json`, `legacy-rule-candidates.json`, `field-routing-report.json`, `field-routing-policy.json`, `control-trace.json`, `paper-parity-audit.cjs`.
5. First 150 historical `field-review/batch-001.json`, `batch-002.json`, `batch-003.json`, `semantic-triage-001-003.json`, `deep-source-recheck-001-003.json`, `field-deep-source-recheck.cjs`, `source-conditional-recheck.cjs`, `r01-hidden-source-audit.cjs`, `field-review/functional-gaps-001-003.json`.
6. Latest executable drafts: `source-books.cjs`, `source-books-fixture.json`, `source-books-demo.cjs`, `source-port-handoff.cjs`, `source-port-handoff-demo.cjs`, `source-books-posting-boundary.cjs`, `source-books-posting-demo.cjs`, all respective `modules/paperops/tests/*.test.cjs`. Read `modules/paperops/README.md` §§5f–5k and its latest appended build updates.

**Count baseline:** 1,246 old original unique keys = 86 previously *linked to critical controls* (**not fully functionally approved**) + 150 source field declaration rechecked (**not real ERP parity**) + 10 new untouched reserved keys + 1,000 Codex-owned. You own **86 + 150 + 10 = 246**, never 236 and never the Codex 1,000.

Your 10 extra keys are exactly:
`R-01:drawer_none`, `R-01:ho_count`, `R-01:ho_range`, `R-01:ho_written`, `R-01:stock_locked`, `R-01:orders_taken`, `R-01:order_range`, `R-01:delivered_n`, `R-01:pending_next`, `R-01:advance_taken`.
These 10 **do NOT count as source-reviewed** yet; do a full original source check first. Codex starts after them with `R-01:board_recon` and does not own any of your 246.

## 1. Branch isolation and source-of-truth discipline

- Use the latest SHA on parent Draft PR #132, with ownership manifest included, as baseline. Create your own isolated build branch `build/chatgpt-paperops-246-20261123`. Open a **Draft PR** targeted to the PaperOps parent branch, or an explicitly coordinated parent-base strategy, never `main` or canonical trunk without separate Owner GO.
- Your writer ownership: `modules/paperops/field-review/chatgpt-246/**`, test files with prefix `chatgpt-246-`, scoped implementation changes within `modules/paperops/` as justified, and your own PR notes. **DO NOT EDIT** Codex's `field-review/codex-1000/**`, `codex-1000-audit.cjs`, `codex-1000-*.test.cjs` or the immutable `ownership-246-1000.json`. Do not touch Claude's trunk, live routes, protected legacy or Supabase.
- External Board/Decision Book: read/write only when authorized and connector works. If not updated say **NOT WRITTEN**. Report exact source SHA, PR link and CI evidence.
- Do not cherry-pick a whole stale historical PR or allocate migrations from someone else's lane. Review reserved NP01/NP03A/NP06 ranges and canonical Control registry. Do not edit already-hosted migrations.

## 2. Existing 11 OPEN functional gaps — close with actual evidence, not relabeling

Read the current `field-review/functional-gaps-001-003.json`. As of initial 150 deep recheck the gaps were:

| ID | Business gap / priority | Expected real correction direction |
|---|---|---|
| `C02-01` | Old blank pay mode means cash; current prototype requires explicit mode | Source evidence + proposed Owner policy; do not change approval policy silently |
| `C02-02` | Missing receipt reason vs yellow/red warning severity | Reproduce exact source severity, follow up on signed approved exception rather than silently clearing |
| `C02-03` | Payment source `money_account_id` uses old source/options | Map to canonical tenant/business/site-scoped Money account with server-verified selection |
| `C01-01` | Cash handover with independent denomination recount/custody | Signed sender/carrier/hub, serial/seal/date, two-person count, cashbook cross-ref and controlled correction |
| `W02-01` | Returnable crate/tray due is entered on original W-02 | Upgrade existing synthetic 5-movement book toward approved source-accountable signed canonical Stock control; no false legacy-computed claim |
| `W02-02` | Conditional cash amount and order number are visible, not old `req` | Exact branch tests; explicit new stricter business policy decision and safe role scoping |
| `W03-01` | Count movement and independence | Freeze/movement reconciliation, independent actor, adjustment authority, audit + reversal |
| `R01-01` | Fridge temperatures, expiry, food safety incident | Verified policy/temps, evidence of monitoring and safe hold/escalation; avoid inventing thresholds |
| `R01-02` | Old `O()/n()` semantic visibility helpers unresolved | Recover helper implementation from untouched old source if provable; true/false/unknown tests; fail closed if uncertain |
| `R01-03` | R-01 daily voucher rows vs C-02 expenses and real cashbook | Extend existing 2-voucher reconciliation to canonical signed Money journal with durable idempotency, no double posting on daily close |
| `R01-04` | Daily float/receipts/advance/refund/digital/deposit/reversal | Real source-linked cashbook reconciliation and originally hidden red/yellow warning branches; no guessed formula |

The existing source-book prototypes, 8 no-write Stock/Money handoff intents and separate 7 draft posting proposals are **implemented and testable**, but **NOT actual signed ERP postings**. Test counts (historically up to 139 and later parent branch tests) measure only executed source/synthetic gates. Do NOT declare 11 gaps closed merely because a digest, JS checks, mock ledger, local queue or printable form exists. Close a gap only with explicit original source rule, actual applicable code, negative test, signed-server evidence where applicable and real Owner policy signoff if required. Otherwise keep `PARTIAL`/`BLOCKED` with exact remaining dependency.

## 3. The remaining 20 high-risk obligations already related to the original 86

Read `control-trace.json` (20 records) and related tests. Reconcile every obligation against current CORE-10 and draft PaperOps: correct source vouchers, custody, cash and bank books, procurement/GRN/PO, stock count/transfer, manufacturing batch/QC, sales orders/invoice/refund/advance, expiry/food safety, independent approval, finance close, and where the actual obligation requires them, audit/replay/reversal.

Twenty obligations are **not necessarily 20 distinct additional defects**; some overlap the 11 gaps. Build one de-duplicated dependency and finding registry keyed by original field IDs plus obligation IDs and original source refs. Prove whether each business obligation is `SOURCE_RULE_VERIFIED`, `PROTOTYPE_BUILT`, `CANONICAL_RUNTIME_INTEGRATED`, `SIGNED_TESTED`, or `OWNER_POLICY_REQUIRED`; record actual path and test. No human data re-entry where master data, computed values, stored source events and ledger references already exist.

## 4. Ten new original R-01 controls — no silent skipping

Deep inspect exactly the reserved ten through untouched original `R-01` body and `calc(e)`:
- `drawer_none`: drawer vs imprest expense separation, evidence and contradictory events;
- `ho_count`, `ho_range`, `ho_written`: how many handovers, register serial continuity, source cross-references and mismatch handling;
- `stock_locked`: physical custody/access and attestation;
- `orders_taken`, `order_range`, `delivered_n`, `pending_next`, `advance_taken`: sales/order/delivery/pending/advance source-to-server accounting relationships, avoiding duplicate POS/order entry.

Record exact original labels EN/BN, type/constructor, conditional show/required, source calculation dependencies, hidden warnings, staffing proof, candidate ERP data origin and targeted tests. If a source behavior depends on future Sales 030x or Finance 040x, preserve the requirement and mark **BLOCKED_DEPENDENCY**, not `DONE`. These are ten reserved **source fields**, not necessarily ten required daily text boxes.

## 5. Execution order: do small real BUILD slices, not another 246-item audit loop

1. Baseline: run ownership gate; inspect latest parent PR #132 vs canonical trunk, critical 20 and 11 gaps; map exact source ID -> canonical ports and known dependencies. Establish `field-review/chatgpt-246/STATUS.md`, `issue-registry.json` and `closure-evidence.json` with 246 keys and fail-closed states. Do not block first code changes waiting for complete theoretical paperwork.
2. Resolve source-dependent logic you can prove locally: reconstruct `O/n` helper where actually visible; cover warning severity; add exact synthetic truth tables, negative/boundary tests and evidence. Never run frozen JS or invent old helper semantics.
3. Continue **Money/Cash priority**: C-02 receipts/threshold and money account scope, C-01 independent custody + ledger backrefs, R-01 old voucher linkage/drawer segregation/full daily close. Use existing source-books and source-port handoff as starting code, but actual canonical signed authorization requires backend RP Cs, RLS, approvals and immutable posting. If that work is owned by NP06, prepare isolated patches/interface contract/needed test; coordinate rather than overwrite Finance migration ownership.
4. Continue **Stock/Returnables priority**: W-02 packaging opening/issue/return/replay/real signed source, W-03 count movement/variance, site and warehouse context, independent checker, authorized corrections. Real 020x Stock ports belong to their owner, coordinate interface and test boundaries.
5. Continue **R-01 source safety & delivery**: exact original expiry/chiller control without fabricated temperatures; custody/shift handover; daily orders, promised/delivered/pending and advances from canonical Sales/Money sources. Avoid duplicate handwritten daily capture. Cross-lane Sales dependencies must be reported rather than hacked with client-only checks.
6. Complete remaining 86-key critical-control traces and 150-key field proofs, including unresolved formulas/options/permissions. Each correction: source proof → minimal scoped code → positive/negative/boundary tests → exact PR commit → regression result → status update. Request Owner policy only for genuine outstanding choices.
7. Final 246 reconciliation: all exactly assigned keys in status report, no key dropped or falsely marked approved; 20 critical obligations + 11 original gaps de-duplicated, each `DONE_WITH_EVIDENCE` or `OPEN_WITH_BLOCKER`. Any real integration/deploy/merge remains gated by specific authorization.

## 6. Test/implementation bar and prohibited shortcuts

Run on Node 22:
```bash
node modules/paperops/legacy-rule-extractor.cjs --check
node modules/paperops/field-routing.cjs --check
node modules/paperops/field-batch-audit.cjs --check
node modules/paperops/field-deep-source-recheck.cjs --check
node modules/paperops/source-conditional-recheck.cjs
node modules/paperops/field-functional-gap-audit.cjs
node --test modules/paperops/tests/*.test.cjs
```
Plus your newly added exact 246 rules, batch status/closure invariant and source-ledger tests. Before any actual production-capable Stock/Finance server change, examine current signed control API shapes in canonical trunk, migration ledger, tenant/scope RLS, source immutable posting and role revocation race. Only if there is a correctly reserved migration and explicit GO, add numbered up/down migrations with PG17 up→down→up, signed and cross-tenant negative tests, replay/race, auth/approval audit and a safe rollback. **No real DB write or migration deployment without Owner authorization.**

A **working demo with 139/139+ test PASS** is not an Owner acceptance, full original formula parity, cash-account approval or a backend integration. Never weaken existing tests or fake signed JWT, physical evidence, role approval or server auth by passing client-supplied IDs. Existing `canPost:false` must stay false until real server attestation exists and Owner explicitly authorizes production-grade integration.

All results in Bangla with exact current commit SHA, affected source IDs, test counts, Draft PR links, whether SQL/Worker/staging/legacy were untouched, and the next unresolved dependency. Give usable work output each session; if unable to finish all 246, commit and report the exact progress rather than suggesting that the job is “done.”

## 7. Safety and collaboration

Never touch old Supabase `kbuhnpqooycqbzrfejcs` or `luoeyyngayxpqecuuijb`. Staging project `rhrqhbyzrhaafynfhdaf` is not authorized for this assignment. No real source/user business data is required, use synthetic data only. No deployment, live Worker rewrite, `main`/trunk merge, modification of frozen old IMG blobs, or code in Codex's 1,000-audit lane. Use only the canonical Auth, Master, Stock, Money, Approval/Audit, Control ports as valid future ERP destinations, not old unsafe direct tables.

**IMMEDIATE NEXT ACTION:** Start actual code/tests addressing the first high-risk evidence-backed correction in your **246** lane, and create a durable progress ledger. Do not re-review the same 150 solely to make another unimplemented report.
