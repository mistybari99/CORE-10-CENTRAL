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

## Owner directive: demo-first full ERP completion

Every build, test, browser walkthrough, dashboard, approval route and cross-module chain uses the canonical fictitious demo identities only. No real person, email inbox, phone number, operational stock, payment, payroll, customer, supplier or business permission is required or requested during this programme.

The demo programme has a fixed execution loop:

1. Give every module a tenant, legal entity, business, site, role and synthetic source-record fixture from the shared demo registry.
2. Exercise a complete happy path plus tenant, business, site, role, expiry, revoke, replay, stale-version, concurrent-request and recovery failures.
3. Make its UI show the same server-authorized result on mobile and desktop.
4. Run the module in the complete Preview database, then record the exact commit, CI and remaining limitation in the existing Decision Book.
5. Merge only a passing, compatible draft into Preview. Main, production and real-user activation remain later gates.

## Builder and final-integration model

Independent builders may produce isolated Draft PRs for assigned module packages. Each package must stay in its namespace, use only demo fixtures, include a handoff, and state its unbuilt integration gaps. It may not add a second auth, ledger, stock, permission or audit system.

Codex owns the final integration path for every such Draft PR:

1. Check the exact source commit, CI and Decision Book scope.
2. Review changed files for overlap with shared contracts and protected Claude/legacy namespaces.
3. Rebase or adapt it to the current Preview head without copying a parallel engine.
4. Install it with all existing modules into one disposable PostgreSQL 17 database.
5. Run signed demo-identity, cross-tenant, deny, expiry, revoke, replay and concurrency tests plus 390/1440 browser checks where it has a UI.
6. Merge the compatible result into Preview and write evidence plus remaining gaps into the same Decision Book.

This means builders can advance modules in parallel while the final integrated ERP remains one coherent system.

## Demo-completion roadmap

| Wave | Integration outcome | Existing work to reconcile |
| --- | --- | --- |
| 0 | Canonical demo registry, business setup, login, site scope, stock and approval permissions | A018/A020/A034, Build01, Build02A |
| 1 | Approval lifecycle, owner/reviewer UI and immutable audit/read models | GOV-002 PR87–99, GOV-003 PR85 |
| 2 | Workforce, leave, payroll preview, assets and expiry-safe cross-module adapters | A051/A053/A054/A055 drafts |
| 3 | Configured setup profiles and 303-site demo scale proof | Build04 PR94 |
| 4 | Purchase, inventory, production and sales source chain | A048/A049 and procurement PR97 |
| 5 | Source-linked journal, reversal, reconciliation and owner reports | FIN-001 PR96 after Wave 4 |
| 6 | Industry packs and CRM/commerce on the shared source chain | Paint PR95, A057 and remaining vertical drafts |
| 7 | Full demo acceptance: two tenants, multiple businesses/sites, all role personas, report drill-downs and end-to-end mobile/desktop journeys | Complete Preview integration matrix |

After Wave 7, real-user onboarding is a separate stabilization phase: create a small approved real-user pilot, test only real-environment differences, fix defects, and keep the demo evidence and release gates intact.
