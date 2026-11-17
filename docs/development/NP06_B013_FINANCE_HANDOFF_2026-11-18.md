# NP06 / B-013 — restartable Finance handoff — 2026-11-18

## Authority / branches

| Item | Live verified value |
|---|---|
| Integration trunk | `ccr-15ed11dd-n3hw5h`; checkpoint `ba1ef9fbec8b46b1f28bfee30d5bc6ffde3e4c3e` |
| Finance 0400 | **Already merged** under Owner GO-F1: PR #108, merge commit `de674020ba3d5d28843d714e701fccd813444c31` |
| Finance 0401 | **Draft PR #115**, `build/chatgpt-np06-finance`; verified combined-code checkpoint `bb4246237331f97ad3a4912057b0c3afb2bbb270` |
| Next isolated AR/AP | `build/chatgpt-np06-arap`, stacked development branch; 0402 stays OUT of #115 until #115 has integration GO |
| Migration reservation | NP06 `0400–0499`; 0401 at PR #115, 0402 isolated |
| Hosted / deploy | GO-2 staging and GO-3 deployment **NOT AUTHORIZED**; no hosted apply, Cloudflare, main, production or IMG-ERP-SG writes |
| Required integration permission | Separate explicit Claude/Owner GO for 0401; Finance lane must NOT merge |

## PR #115 mergeability investigation

Previously GitHub reported `mergeable=false` in normalized metadata but raw PR API showed `mergeable=null, mergeable_state=unknown` while trunk had advanced beyond Finance by four commits. Latest Claude trunk contained 0152 Master read, 0153 request-key concurrency guard and Master UI (including `ba1ef9f`). Compared the true common base `cdd21ccd` against Finance and trunk: **zero overlapping paths**. Preserved all six Finance-only files, created a regular two-parent Git merge `bb424623` (parents previous Finance `9f3ffa3` and trunk `ba1ef9f`), pushed with expected SHA and `force=false`. GitHub then reported **mergeable=true, mergeable_state=clean, 0 behind**; PR remained Draft and unmerged.

## Executed exact-code-head CI checkpoint at bb424623 — 4/4 SUCCESS

1. Finance PG17: https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/44165517078
   - Full numbered migrations through 0401 Up→Down→Up, idempotent reapply, naming/order contracts, registry/evidence
   - Existing Finance 0400 E2E and 0401 reversal E2E: immutable posted source and reversal link, exact opposite balanced entries, missing GOV-002 approval fail-closed, Control disabled, tenant/auth denials, replay conflicts, Audit chain, no reversal-of-reversal
   - Independent PostgreSQL sessions: journal post-once and reversal-once; data-bearing rollback is refused
2. S0 migrations: https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/44165517034
3. S1-c canonical approval/audit: https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/44165516995
4. NP02 Owner Control / Master: https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/44165517070
   - Master SQL/RPC cases, Master concurrent sessions, Control registry, legacy migration drift gate, Control/Master browser checks at 390 and 1440 px

**Note:** `bb424623` is the verified code checkpoint; if this handoff or tests are later committed, only cite exact-head check results when rerun on the new head.

## Integration reviewer instructions

1. Re-fetch live trunk and Draft PR #115 head/mergeability. Inspect diff: only `0401` up/down, reversal E2E/race, Finance CI and NP06 increment 2 docs, plus this restartable handoff.
2. Verify the 0401 reversal is the opposite posted journal **through the existing** canonical draft→validate→post chain; original remains unchanged; period/amount/Owner Control/zero-stage policy/receipts are not bypassed.
3. Recheck current trunk merge base, all four CI suites, signed Auth and GOV-002 adapter gaps. **Do not self-merge**; request Owner GO and Claude technical review before integration.
4. Owner Control `finance.journal_reverse` defaults OFF. Existing `finance.journal_post` defaults 1-stage, so nonzero-stage approval stays `FIN_APPROVAL_NOT_CONNECTED`. Synthetic zero-stage tests do not authorize real-world posting.
5. Keep 0402 on `build/chatgpt-np06-arap`. It references 0401 and NP02 `master_parties_v1` and **must not be merged/applied until 0401 is integrated**.

## Remaining B-013 gaps and next actions

AR/AP payment allocations and aging, NP03B Sales and NP03A Procurement source attestation, valuation/COGS, reconciliation, signed Accountant/Cashier policy and 16 persona tests, actual GOV-002 Finance completion adapter, Finance Central Shell UI, hosted signed Auth and accounting/tax/localization certification remain outside **0401** and are NOT VERIFIED COMPLETE. Isolated 0402 is a candidate under its own PostgreSQL CI, NOT production ready.

Shared coordination: Board row B-013 and Master Decision Book change register should link PR #115 with the verified SHA/runs and the isolated F3 branch. Trunk owner Claude controls merging and hosted migration ordering.
