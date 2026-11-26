# CORE-10-CENTRAL — CODEX LANE A: EXACT 1,000 ORIGINAL FIELD SOURCE AUDIT

**Owner delegation: 23 November 2026. Scope lock: 1,000 and only 1,000 distinct original source field IDs, in 20 batches of exactly 50.** This is NEW work in a separate Codex chat. Do not take over the ChatGPT correction lane.

## 0. MANDATORY FIRST READ — no guessed context

Repository: `mistybari99/CORE-10-CENTRAL`. Canonical integration trunk: `ccr-15ed11dd-n3hw5h` (do not commit to it). PaperOps parent Draft PR **#132** at `build/paperops-foundation-20261122`. Use the **current source at this branch** (never assume an old SHA is still HEAD).

Read in this order, completely for relevant sections:

1. `docs/development/AGENT_HANDOVER_CURRENT.md` §§1–4,7 and safety restrictions. Read `docs/development/CLAUDE_TRUNK_HANDOFF.md` top and `docs/coordination/WORK_SPLIT_AND_PROTOCOL.md`.
2. `modules/paperops/field-review/ownership-246-1000.json` — **authoritative, exact field ID array**: `lane_A_codex.ownership_keys` (1,000). DO NOT recompute a different population if a report is out of date.
3. `modules/paperops/field-routing-report.json` (all 1,246) and `modules/paperops/field-routing.cjs`; `modules/paperops/legacy-field-index.json` and `modules/paperops/legacy-rule-candidates.json`.
4. **Original immutable source:** `legacy/islamia-erp/forms.js` (and the preserved other old Islamia files only if an original helper/flag truly requires them). Read original source as **text**; never load/evaluate/run old code, connect it to Supabase, copy legacy config, or modify any old byte.
5. Historical batches `modules/paperops/field-review/batch-001.json`, `batch-002.json`, `batch-003.json`; `field-batch-audit.cjs`, `field-deep-source-recheck.cjs`, `source-conditional-recheck.cjs`, `field-semantic-triage.cjs`, `r01-hidden-source-audit.cjs`, `field-review/functional-gaps-001-003.json`, `modules/paperops/README.md`.
6. Current tests `modules/paperops/tests/*.test.cjs`; especially `ownership-split-246-1000.test.cjs`. PR #132 controls are draft-only; do not declare them production postings.

The source's 1,246 original keys comprise **86 already high-risk-control-linked + 150 already source-rechecked in historical batches + 10 reserved for ChatGPT + your exact 1,000**. Initial first-pass pending before earlier batches = 1,160. After historical 150 = 1,010; first ten belong to ChatGPT; 1,000 remain yours.

**Your FIRST key:** `R-01:board_recon`. **Your LAST key:** `F-01:owner`. The first 10 of the previous unreviewed queue belong exclusively to ChatGPT: `R-01:drawer_none`, `R-01:ho_count`, `R-01:ho_range`, `R-01:ho_written`, `R-01:stock_locked`, `R-01:orders_taken`, `R-01:order_range`, `R-01:delivered_n`, `R-01:pending_next`, `R-01:advance_taken`. **Never review or report those as part of your 1,000.**

## 1. Branch/ownership: do not overwrite other builders

- Create an isolated new branch, suggested `audit/codex-paperops-1000-20261123`, based on the **PaperOps parent Draft PR #132 branch HEAD with the ownership manifest present**. Open a separate **DRAFT** PR targeting `build/paperops-foundation-20261122` (or explicitly describe any repository PR base restrictions), NOT `main` or the canonical trunk. Do not merge, deploy, apply SQL, or write real ERP data.
- You may edit/create ONLY `modules/paperops/field-review/codex-1000/**`, a dedicated reproducible audit tool such as `modules/paperops/codex-1000-audit.cjs`, corresponding distinct `modules/paperops/tests/codex-1000-*.test.cjs`, and your own lane report/README inside `field-review/codex-1000/`. If CI needs a new workflow, use a uniquely named Codex workflow; never replace another lane's workflow or test.
- **DO NOT EDIT** `ownership-246-1000.json`, `field-batch-audit.cjs`, `field-review/batch-001..003.json`, `field-review/chatgpt-246/**`, `source-books*.cjs`, `source-port-handoff.cjs`, posting/finance/stock modules, canonical migrations, live app/shell, prior source extraction, frozen old sources, or other builders' branches. Any discovered error in shared files is a **finding for the ChatGPT lane**, not a silent edit.
- Commit one complete evidence batch at a time; record commit SHA + passing tests + counts. Preserve partial work durably on your branch. Do not start the next batch until the current batch's source proof and test gate pass.
- Coordination board/Decision Book: write a scoped row if connected/authorized; otherwise put **NOT WRITTEN** in your PR/report. Never claim an external board write you did not perform.

## 2. Batch algorithm — STRICT 20 × 50 with no overlap

Source of truth is the manifest's `lane_A_codex.ownership_keys`, indexed from zero.

For batch `A001`, use `keys.slice(0,50)`; `A002` uses `slice(50,100)`; ...; `A020` uses `slice(950,1000)`. Every 50 must be in **exact manifest order**. Use `batch-A001.json` ... `batch-A020.json` in `modules/paperops/field-review/codex-1000/`. Historical `batch-001..003` are the OLD first 150, not part of your 20, and `field-batch-audit.cjs` must NOT be tricked into treating ChatGPT's reserved 10 as previously completed 50.

Your dedicated `codex-1000-audit.cjs` should validate:
- Every manifest key appears once, in exactly one of the twenty assigned batches; no missing, duplicate, reordered, reassigned, fabricated or newly renamed IDs.
- Every source field has its original `form:key`, exact Bangla and English labels, constructor/type, `req/show/who` syntax and source evidence; match to `legacy/islamia-erp/forms.js` as immutable read-only text. Store short, specific source fragments/offsets or hashes; do not copy enormous old source bodies or execute it.
- Batch proof cannot set `owner_accepted`, `field_parity_certified`, `source_runtime_equivalent` or `production_ready` to true. CI must detect false approvals and incomplete batches.
- 20 reports in proper order => 1,000 unique, + 246 protected = 1,246; no silent source changes. Existing 86 and 150 are not to be audited as part of your count.

## 3. For EACH of the 50 fields: deep operational source investigation

For each exact source key, document in machine-readable report:
- Old original form ID, field key, EN/BN label, original constructor alias, input type, requirement `req`, conditional visibility `show`, role `who`, default, alternatives/options/list, linked source references and row/collection membership.
- **Old runtime/business behavior**, to the extent actually provable from frozen source: `calc(e)` formula and its dependencies, visible/required conditions and false/true/unknown branch, warning codes **and severity**, currency/quantity/UOM precision, sign/rounding/negative/zero edge cases; supporting settings and helper `O()/n()` status (mark `UNKNOWN` if unreconstructed).
- Data classification for new CORE-10: user-entered only when necessary, master reference, server-generated/calc display, event-triggered source voucher, ongoing ledger, external signed evidence, multi-row collection, human attestation, optional/conditional, or **UNRESOLVED**. **Do NOT turn 1,000 old keys into 1,000 new mandatory daily ERP inputs.**
- Required separation of duties, actor/tenant/business/site and account scope, approval chain, source receipt/serial, physical stock/cash custody, upstream/downstream Money/Stock/Sales/Manufacturing references; retain source proof without copying old unsafe persistence behavior.
- Current target, if actually present: path to a proposed CORE-10 module/form/print field/RPC; else `NOT_BUILT`. State whether old source behavior is proven, partial or unknown. A printable label, source static pattern or mock test does NOT establish full business-rule parity.
- At least one **positive**, **negative/abuse**, and **boundary** synthetic test case for each distinct executable rule/condition group; do not create duplicate throwaway tests for simple display-only fields. Distinguish evidence `SOURCE_PROVED`, `PROTOTYPE_PROVED`, `CANONICAL_SERVER_PROVED`, `UNKNOWN`.
- Finding IDs like `A001-F003` with exact original field IDs, short quote/offset/hash, severity, missing control, reproduction, dependency, suggested safe resolution and owning correction lane (ChatGPT B). Mark `BLOCKED_OWNER_POLICY` only for genuinely undecided business policy.

Static extractor may miss **dynamic warnings**; previous R-01 source audit already found 5 missed dynamic cash/goods/temperature warnings. The 163 candidate warnings are **not exhaustive**. Study conditional scripts and helpers, not just regex field declarations. Do not invent formula certainty when original helper semantics cannot be recovered.

## 4. Deliverables and acceptance gates per batch

`batch-A###.json` should have an explicit schema/version, source provenance (immutable form and old-file hashes or original excerpts/offsets), batch `A###`, exact 50 source IDs and per-field evidence, conditional/formula map, source warning/severity map, proposed data origins, risk/issues, test cases, confidence/unknowns, and `owner_accepted:false`, `parity_certified:false`, `erp_posted:false`. Use a separate consolidated `issues.json` or JSONL with stable IDs linked to fields, reviewed batch and distinct correction handoff descriptions. Provide Markdown `PROGRESS.md` (completed batch count, unique keys, 1,000 minus checked, finding counts, CI proof, unresolved high-risk, next 50). Each batch's 50 keys must be exact.

Tests required: ownership gate, actual source labels, constructor aliases, required/conditional branches, invented-field mutation, source drift, duplicate/reordered/missing IDs, false approvals, positive/negative/boundary rule examples. The existing PaperOps global suites and cross-module old-IMG guard must remain green on your branch (run Node 22).

Reproduce:
```bash
node modules/paperops/legacy-rule-extractor.cjs --check
node modules/paperops/field-routing.cjs --check
node modules/paperops/field-batch-audit.cjs --check
node --test modules/paperops/tests/ownership-split-246-1000.test.cjs
node --test modules/paperops/tests/*.test.cjs
# plus your new codex-1000 audit CLI and own tests
```

Run CI at the **exact GitHub PR HEAD** and report the actual workflow URL/count. If red, fix your own report/tests; do not disable gates or soften old contracts. A report is complete when its original 50 and evidence/tests are complete; **business parity is not certified**.

## 5. Reporting to the Owner / handoff to ChatGPT

After each A###: in concise Bangla report **50/50 source keys checked, batch range and forms, provable rules, number of high/medium/low gaps, current source evidence, exact commit SHA, tests, number remaining**, and share the dedicated issues artifact GitHub link. Real unresolved high-risk blockers should be immediately surfaced, not buried for another 950 fields.

The independent ChatGPT correction lane owns `86 + 150 + 10 = 246` and may use Codex's 1,000 issues **as input for future fixes**, but your 1,000 remain audit-only. NEVER mark an audit issue “fixed” just because you handed it over; ChatGPT must independently attach a code commit, negative regression test, canonical integration evidence or legitimate Owner decision.

At the end of batch A020, hand over **1,000 unique source evidence rows, 20 complete 50-item batches, grouped gap matrix, source dependency tree, a duplicate-proof summary and exact green CI URLs**; 0 invented real-live approvals. No merge/deploy until independently approved.

## 6. Safety invariants

Do not touch the retired Supabase projects `kbuhnpqooycqbzrfejcs` or `luoeyyngayxpqecuuijb`. Staging `rhrqhbyzrhaafynfhdaf` is NOT an authorization to query or write it. No Worker deployment, no secrets, no real financial posting, no `main`/trunk merges, no old source execution, no changes to preserved legacy byte hashes. Use synthetic values and never leak customer data. Respect canonical NP01/NP02/NP03A/NP06 ownership boundaries; do not allocate migrations.

**IMMEDIATE NEXT ACTION:** Read the current ownership manifest and start actual `A001` first 50 from `R-01:board_recon`. Produce code + source-backed report + exact tests on your isolated audit branch. Do not produce merely another roadmap.
