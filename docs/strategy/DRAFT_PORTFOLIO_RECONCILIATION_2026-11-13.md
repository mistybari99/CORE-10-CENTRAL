# Draft portfolio reconciliation and next build sequence

This is an implementation sequencing record. The Master Decision Book remains the authority for scope, policy and release decisions.

## Verified baseline

Build 01 is merged to the Preview integration branch at `57b1b95fa4592b1c3c4fd52296e71af6ab5b6971`. Its exact-head remote CI passed at `9a57a3bdb7250c58869475d49720d504d1d515fc`: local GoTrue, PostgreSQL 17, browser widths 390/1440, setup replay, site grants, explicit stock deny, expiry, revoke, audit and the complete existing Preview regression matrix.

The implementation covers the shared chain below, with fictitious local identities only:

```text
sign-in → legal entity → draft business → site → membership/site policy
        → stock.read | stock.post effective decision → revoke → audit
```

It does not yet provide approval-specific actions, universal module expiry adapters, hosted staging or production certification.

## Draft inventory and disposition

| Track | Current evidence | Reconciliation needed before merge/release |
| --- | --- | --- |
| GOV-002 approval chain, PRs 87–99 | Significant isolated SQL, client, UI and race tests; PR89 proves compatibility with an older pinned Build01 commit | One current shared approval-action resolver; rebase the stacked chain on Preview; real signed auth test; keep typed domain ports blocked until a canonical source is certified |
| GOV-003, PR85 | 12-feature isolated audit/readiness draft with PG17 CI | Consume canonical events and current signed scope; preserve advisory status; no duplicate audit or permission engine |
| Setup profiles, PR94 | Ten-family advisory profiles, site fixture and preflight tests | Make it call Build01 context and receipt endpoints; validate 303-site loading and rollback with actual local GoTrue |
| Paint/hardware, PR95 | Isolated recipe/QC durable demo plus non-posting dealer workflows | Connect only through A048/A049 source movements and FIN-001 after their contracts are certified; do not create shadow stock or ledger |
| Procurement, PR97 | In-memory workflow kernel | Replace submitted actor and memory state with canonical signed SQL/RLS and approved source adapters before any merge |
| Finance, PR96 | Balanced journal proposal and reversal boundary | One transactional signed posting service over certified A049 sources; no parallel ledger; GoTrue, concurrency, rollback and recovery proof required |
| A051/A053/A054/A055/A057 Claude packages | Existing separate ownership and isolated implementations | Preserve their source namespaces. Reconcile through adapters and tests only after exact branch/CI review; no direct rewrite |

## Build order

1. **Build 02A — shared approval permissions.** Add approval action definitions to the existing Build01 canonical engine: `approval.submit`, `approval.decide`, `approval.delegate`, `approval.withdraw`, `approval.export` and `approval.exception`. The server derives current signed actor and business/site scope; explicit deny wins; expiry/revoke is checked at execution. It must not infer an approval right from stock rights or UI visibility.
2. **Build 02B — GOV-002 reconciliation.** Rebase the approved subset of the GOV-002 stack on the current Preview branch, make its signed RPCs consume Build 02A, and run GoTrue, tenant/business/site, maker-checker, expiry, deny, replay and concurrent-decision tests.
3. **Build 04 — Setup profiles.** Connect the existing profile/preflight draft to Build01's context/setup receipt, then prove 303-site replay, rollback and scope denials.
4. **Build 08 → Build 11.** Convert procurement from its in-memory draft into canonical source documents and bounded receipts; only then connect a source-linked finance journal proposal/posting boundary.
5. **Industry packs.** Bring paint/hardware and the other verticals through the same inventory, operations, approval and finance contracts one vertical at a time.
6. **Cross-module adapters.** Add A051/A055 expiry adapters and owner-only summaries without changing Claude-owned implementation namespaces.

## Build 02A acceptance

- No new membership, permission or audit table; reuse Build01 membership/site grant and original access-event history.
- An approval action has no implicit default from `stock.read` or `stock.post`.
- A matching current business role can receive a time-bounded grant; an explicit user/site deny beats inherited role allowance.
- Expired or revoked membership fails at RPC execution even with a still-valid signed session.
- A foreign tenant, other business, anonymous caller, forged user metadata, stale request, duplicate replay and direct table write are denied.
- Tests use disposable PostgreSQL 17 and local GoTrue only. The result remains isolated until separately approved for staging or release.

## Work started

The next branch starts Build 02A on the Preview integration head. Its first deliverable is the additive action resolver and its signed-server test suite. GOV-002 source is deliberately not copied until that contract passes.
