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

### Verified local execution (2026-11-11)

- Real PostgreSQL **17.9** server; psql **17.11** client, both isolated under `/tmp/core10-pg17.jg50ff`. All seven initial combined-schema suites passed. Temporary test databases were removed by the runner.
- Expanded original CRM, A051 and A054 concurrency tests passed on combined schemas. All five A055 per-area suites, integrated suite, six race scenarios and the client/catalog/SQL contract passed on combined schemas.
- Original A055 signed-HMAC PostgREST **12.2.12** API suite and original Assets browser at 390/1440 passed on a fresh combined schema. This includes signature/expiry/forged-role, foreign-tenant, direct-table/helper denial and actual work-order/report paths. It remains synthetic identity proof, not GoTrue.
- Original A052 browser passed at 390/1440 using actual combined PostgreSQL through its original psql bridge. Original A045 and A053/A054 browser fixture journeys passed against the packaged public artifact.
- Worker safety/module route tests, artifact injection tests, actual HTTP denial, original legacy mobile/offline smoke, deterministic factory and 116/116 capability-registry validation passed.
- Public HTTP smoke: **4/4 passed**. Public deployed browser: original operations/inventory scope switch and disabled writes, CRM lead/enquiry/opportunity, all eight CRM entries and tenant isolation passed at 390/1440. The environment's browser proxy required an explicit certificate-error override; this is UI evidence, not TLS certification. Independent curl/Node HTTP checks used normal environment certificate trust.
- GitHub Actions runs were queued with no started jobs at this checkpoint; local results must not be relabelled as remote CI success. Recheck the eventual results for the final commit.

Original module scripts with real dependencies remain real: A052 UI tests run while its combined PostgreSQL database is alive; A055 HTTP/UI tests run with signed-HMAC PostgREST against a fresh combined database. They do not run as disconnected fixture-only checks.

A055 concurrency deliberately retains an open breakdown. HTTP tests require their own clean baseline, so they get a separate fresh combined database; race evidence is retained rather than deleted. The original A055 race script's isolated loader is omitted in-memory only after verifying its exact bootstrap lines, while every race assertion remains unchanged.
