# Preview One completion and module integration

Owner direction: complete usable modules, reuse draft PR implementations, integrate them, and deliver Preview One first. This is an execution checklist beneath the existing Decision Book, not a replacement policy register.

## Release sequence

1. Preserve original module commits and merge compatible branch histories into `codex/preview-one-completion-20261111`.
2. Install the entire combined migration stack in disposable PostgreSQL17. Run seven suites after all migrations: cross-module purchase/stock/sale/portfolio/workforce/CRM identity, original operations, intent, CRM, workforce after policy hooks, workforce policy/integration, assets.
3. Run original browser journeys against the verified public artifact. Reject SQL, documentation, internal code, secrets and symlinks over the actual HTTP fixture.
4. Publish tested synthetic preview routes. Original Workshop and CRM are runnable synthetic demos; original Inventory and Operations show a read-only regression snapshot. No UI demo substitutes for signed database evidence.
5. Merge integration PR #74 into the preview branch only after combined checks pass. PR #70 already merged to preview at `68b9cab5c7ed10aaec0c2c05ac59c8bd92ad74a4`.
6. Complete each remaining module gap below with canonical handlers, positive/negative tests and a usable UI. Re-run affected combined suites before accepting that module as complete.
7. Run authorized staging identity/RLS and end-to-end operational certification before a separate production release. Preserve historical business records and REV-009 throughout.

## Source reconciliation

| Module | Original PR / imported head | Current disposition and completion gate |
|---|---|---|
| A045 Workshop | #42 / `18882eb` | Original source and history integrated; omitted shared Studio links/projection restored. One advisory registered handler, not arbitrary operational execution. |
| A046 personas | #44 / `ca2c682` | Original synthetic roster preserved and reused by combined database setup. |
| A047 sites | #45 / `e14a0b1` | Original canonical site topology preserved; signed staging and scale measurement remain. |
| A048 inventory | #49 / `b5f7ac9` | Existing source preserved through original stacked ancestry; combined stock tests and original read-only UI route added. |
| A049 operations | #50 / `60a3c3d` | Existing source preserved; actual purchase/stock/sale combined test. Production remains a plan; certified COGS/GL not implemented by this module. |
| A050 portfolio | #51 / `e31c9e3` | Original ancestry integrated; canonical operation/workforce read-model integration tested together. |
| A051 workforce | #55 / `8104d0c` | Original source/history integrated. Re-run original regressions after A054 hooks. Approval and liabilities never imply payment. |
| A052 intent | #62 / `4451289` | Actual source imported unchanged despite stale assignment-only title; five advisory capabilities. Additional handlers and operational enforcement remain scoped engineering work. |
| A053/A054 workforce policy | #63 / `3a41251` | Actual source imported unchanged; combined tests must prove hooks retain A051 invariants. |
| A055 assets | #59 / `5a6e9e2` | Actual source imported unchanged; combined integrated test and original UI suite. Canonical A021/A034 grant reconciliation remains a release requirement. |
| A056 CRM | #66 / `3936e1e` | Actual source imported unchanged; runnable original synthetic demo routes plus combined SQL regression. Real finance/provider delivery stays uncertified/no-op. |
| A057 commerce | #65 / `e3b1dcf` | Work order only; runtime missing. Preserve Claude reservation; integrate completed delivery when available. |
| Quality/lot/recall | #73 / `1214731` | Dedicated tests green; excluded from first combined stack because tracked-stock anti-bypass requires explicit A048/A049 compatibility engineering. |

Already identical module blobs were not recopied or rewritten. Original merge histories are retained. Workflow conflicts keep the preview branch's broader UI path triggers and client tests; handoff conflicts retain both historical module sections.

## Module definition of done

For each supported workflow: canonical identity and permission checks; complete supported state transitions; connected upstream/downstream records; immutable audit and replay safety; exact quantities/money with reversals; source-linked reports; usable responsive UI with guidance; positive, tenant-negative, stale/replay and concurrency tests. Record code SHA, test environment, CI run, preview route and known limits in the Decision Book. A dedicated green module test does not establish combined compatibility or production readiness.

## Evidence boundaries

Local browser coverage includes 390px and 1440px, original CRM lead-to-order/support/consent/tenant journey through the Worker, original Inventory/Operations rendering and scope switch, and private-path HTTP denial. GitHub PostgreSQL17 matrix runs are separate evidence; a queued run is not a pass. No production database, live staff/payment/provider operation, paid-service activation or main merge is part of this preview integration.
