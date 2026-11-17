# NP06 / B-013 — restartable Finance handoff — 2026-11-18

## Authority / branches

| Item | Live verified value |
|---|---|
| Integration trunk | `ccr-15ed11dd-n3hw5h`; checkpoint `ba1ef9fbec8b46b1f28bfee30d5bc6ffde3e4c3e` |
| Finance 0400 | **Already merged** under Owner GO-F1: PR #108, merge commit `de674020ba3d5d28843d714e701fccd813444c31` |
| Finance 0401 | **Draft PR #115**, `build/chatgpt-np06-finance`; Claude-review hardening changes pushed (final exact-head CI to verify after documentation commit) |
| Next isolated AR/AP | `build/chatgpt-np06-arap`, **Draft stacked PR #117** (0402–0403), based on F2 branch, stays OUT of PR #115; no merge before separate Owner GO |
| Migration reservation | NP06 `0400–0499`; 0401 at PR #115, 0402–0403 isolated in PR #117 |
| Hosted / deploy | GO-2 staging and GO-3 deployment **NOT AUTHORIZED**; no hosted apply, Cloudflare, main, production or IMG-ERP-SG writes |
| Required integration permission | Separate explicit Claude/Owner GO for 0401; Finance lane must NOT merge |

## PR #115 mergeability investigation

Previously GitHub reported `mergeable=false` in normalized metadata but raw PR API showed `mergeable=null, mergeable_state=unknown` while trunk had advanced beyond Finance by four commits. Latest Claude trunk contained 0152 Master read, 0153 request-key concurrency guard and Master UI (including `ba1ef9f`). Compared the true common base `cdd21ccd` against Finance and trunk: **zero overlapping paths**. Preserved all six Finance-only files, created a regular two-parent Git merge `bb424623` (parents previous Finance `9f3ffa3` and trunk `ba1ef9f`), pushed with expected SHA and `force=false`. GitHub then reported **mergeable=true, mergeable_state=clean, 0 behind**; PR remained Draft and unmerged. A further negative Control OFF-after-replay test was added without changing the reversal migration; 4/4 checks also passed at `bcb3b6f`.

## Executed exact-code-head CI checkpoint at bcb3b6f — 4/4 SUCCESS

1. Finance PG17: https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/44167160122
   - Full numbered migrations through 0401 Up→Down→Up, idempotent reapply, naming/order contracts, registry/evidence
   - Existing Finance 0400 E2E and 0401 reversal E2E: immutable posted source and reversal link, exact opposite balanced entries, missing GOV-002 approval fail-closed, Control disabled, tenant/auth denials, replay conflicts, Audit chain, no reversal-of-reversal
   - Independent PostgreSQL sessions: journal post-once and reversal-once; data-bearing rollback is refused
2. S0 migrations: https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/44167160113
3. S1-c canonical approval/audit: https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/44167160598
4. NP02 Owner Control / Master: https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/44167160637
   - Master SQL/RPC cases, Master concurrent sessions, Control registry, legacy migration drift gate, Control/Master browser checks at 390 and 1440 px

**Note:** `bcb3b6f` is a verified code checkpoint; subsequent documentation/test commits may advance the branch head. Recheck PR #115 and CI at its actual current SHA before any integration claim.

## 2026-11-18 — accepted Claude independent review, Owner final security hardening (0401)

Reviewed comment: https://github.com/mistybari99/CORE-10-CENTRAL/pull/115#issuecomment-6959682421 . Owner accepted that technical review, but **authorized hardening only**, not trunk integration, hosted staging or deployment.

**Changed ONLY the unmerged Finance F2 branch:**

1. **Authorization-before-lock:** `finance_reverse_posted_journal_v1` now first reads only `tenant_id,business_id` from the original journal with no row lock, verifies signed `actor_uid` + canonical `can_manage`, **then** acquires `FOR UPDATE` and rechecks the locked row's tenant/business scope and current permissions. A cross-tenant caller gets `FIN_AUTH_DENIED` without being able to hold or wait on a foreign journal lock. Authorized reversals retain one-row serialization, immutable original, protected Audit and all draft/validate/post gates. No integrated migration (0400 or NP01) was modified.
2. **Live Owner Control even on replay:** `control_check_v1` remains **after authorization and the authorized source lock but BEFORE prior reversal/idempotency lookup**. This is intentional fail-closed behavior: disabling `finance.journal_reverse` invalidates *new requests and identical retries*. It does not delete historical posted reversals. The existing `np06-finance-reversal-e2e.sql` explicitly proves the disabled exact-key retry returns `CONTROL_DISABLED:finance.journal_reverse`.
3. **Standalone two-session race:** `tests/migrations/np06-finance-reversal-race.sh` now self-seeds an already-posted source from its **own** dedicated `np06-finance-reversal-race-seed.sql` when the earlier Finance posting-race has not run. The regular combined CI still runs posting race first, reversal race second. **Additionally**, the Finance CI creates an empty, separate PostgreSQL 17 database, runs all migrations and invokes only the reversal race (without the posting race), verifying exact-one posted reversal, single immutable link/audit.
4. **Blocked foreign lock proof:** the reversal race also starts a real second PostgreSQL session holding `FOR UPDATE` on the posted source; a *valid owner of another tenant* attempts reversal with 350ms `lock_timeout`. The expected `FIN_AUTH_DENIED` is asserted while the source remains locked. A pre-authorization lock would instead time out and fail the test.
5. **NP01 B-020 combined compatibility:** `.github/workflows/core10-np06-finance-ci.yml` now has an isolated disposable PostgreSQL 17 job that **read-only fetches** NP01 Draft PR #111 at pinned SHA `c858084d0d5a80b752637c30fd7c9199dc8455a5`, creates a **local non-pushed** combined merge with the F2 checkpoint and runs migration Up/Down/Up, Master, NP01 0110–0112 submit/route/site, Finance reversal E2E and real concurrency scripts. The CI token is contents-read only, and the head pin aborts if NP01 PR #111 changes unexpectedly. This neither merges into Claude trunk nor modifies PR #111.

**Compatibility / deployment gates:** The Owner's actual 0401 integration GO is **still pending**. NP01 0110–0149 migration reservation is **not released for hosted use**, so the separate GO-2 hosted migration remains unauthorized regardless of CI. GOV-002 1+stage Finance posting still correctly fails `FIN_APPROVAL_NOT_CONNECTED`. No staging, Cloudflare, production, main or IMG-ERP-SG writes.

**Final checkpoint verification:** once this documentation commit lands, confirm all four F2 shared suites (Finance PG17 *both jobs*, S0 migrations, S1-c Approval/Audit, NP02 Master/Owner Control + browser) at the latest actual PR #115 head. Do not infer exact-head PASS from earlier commits. Also check PR #117 remains Draft/unmerged and isolated.

## Integration reviewer instructions

1. Re-fetch live trunk and Draft PR #115 head/mergeability. Inspect diff: only `0401` up/down, reversal E2E/race, Finance CI and NP06 increment 2 docs, plus this restartable handoff.
2. Verify the 0401 reversal is the opposite posted journal **through the existing** canonical draft→validate→post chain; original remains unchanged; period/amount/Owner Control/zero-stage policy/receipts are not bypassed.
3. Recheck current trunk merge base, all four CI suites, signed Auth and GOV-002 adapter gaps. **Do not self-merge**; request Owner GO and Claude technical review before integration.
4. Owner Control `finance.journal_reverse` defaults OFF. Existing `finance.journal_post` defaults 1-stage, so nonzero-stage approval stays `FIN_APPROVAL_NOT_CONNECTED`. Synthetic zero-stage tests do not authorize real-world posting.
5. Keep 0402 on `build/chatgpt-np06-arap`. It references 0401 and NP02 `master_parties_v1` and **must not be merged/applied until 0401 is integrated**.

## Isolated next increment: actual code exists, NOT mergeable before 0401

The independent development branch `build/chatgpt-np06-arap` was created from the earlier 0401 combined checkpoint before the additional PR #115 evidence. It contains 0402–0403 outside PR #115 in stacked Draft PR #117: canonical NP02 `master_parties_v1` AR/AP source links, immutable allocations between already-posted canonical Money journals, derived as-of aging, default-OFF Owner Control, scoped Auth/RLS/Audit and two-session replay/overspend cap. It stores **no second journal, party directory or mutable balance**. Disposable PG17 exact-head `ff1c02c3d32fcbc2a37149b691e16a5cf1344524` CI **SUCCESS**: https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/44167343936. Full details: `docs/development/NP06_B013_ARAP_INCREMENT3_ISOLATED.md` on that separate branch.

0402 is stacked on the 0401 candidate and **must not be integrated until PR #115 is independently reviewed and merged with Owner GO**. The F3 branch is not part of PR #115, and PR #117 is a stacked Draft based on F2 only, **not** a trunk integration request.

## Remaining B-013 gaps and next actions

AR/AP payment allocations and aging, NP03B Sales and NP03A Procurement source attestation, valuation/COGS, reconciliation, signed Accountant/Cashier policy and 16 persona tests, actual GOV-002 Finance completion adapter, Finance Central Shell UI, hosted signed Auth and accounting/tax/localization certification remain outside **0401** and are NOT VERIFIED COMPLETE. Isolated 0402–0403 is in Draft stacked PR #117 with separate disposable PostgreSQL CI; NOT production ready.

Shared coordination: Board row B-013 and Master Decision Book change register should link PR #115 with the verified SHA/runs and the isolated F3 branch. Trunk owner Claude controls merging and hosted migration ordering.
