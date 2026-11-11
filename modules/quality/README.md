# C10-A058 — Enterprise Quality, Lot / Expiry Traceability, Quarantine & Recall

**Owner request:** Work independently during Codex usage limit without touching Claude or Codex's work.  
**Issue:** https://github.com/mistybari99/CORE-10-CENTRAL/issues/72  
**Draft PR:** https://github.com/mistybari99/CORE-10-CENTRAL/pull/73  
**Dependency:** Draft PR #7 demo foundation. Isolated c10_demo PostgreSQL17; not the production Supabase SG.

## Implemented runnable code

1. Tracked-item enrollment prevents silently adopting existing positive untracked stock.
2. Lot registration with business/item/site, source reference, manufacture and expiry dates; exact idempotency.
3. Checklist inspection, owner-only release/hold/reject, mandatory passing inspection, expiry/recall safety.
4. Lot receipt, issue, two-site transfer, waste/recall disposal via the **canonical A018 demo stock RPC** with one-use stock-permit guard. One transaction updates both stock and lot views; no shadow canonical stock.
5. Graph genealogy parent -> child with same-business and cycle checks, cascading recall and zero-remaining-stock closure.
6. FEFO earliest-expiring pick recommendation without suggesting quarantined/expired lots.
7. Tenant/site RLS scoped reports, audit, lot balances, stock ledger reconciliation, idempotent requests and rollback.
8. Strongly validated client adapter, self-contained fictitious in-memory model and task-driven Bengali-first web preview.

## Deliverable locations

| File | Role |
| --- | --- |
| internal/enterprise-sql/c10_a058_quality_lot_recall_v1.sql | Relational domain model, RLS, stateful APIs, anti-bypass trigger |
| tests/c10_a058_quality_e2e.sql | Reproducible synthetic SQL end-to-end positive/negative tests |
| .github/workflows/core10-a058-quality-ci.yml | Disposable PostgreSQL 17 + Node tests |
| modules/quality/quality-client.mjs | Checked RPC/view adapter; disabled unless disposable mode is explicit |
| modules/quality/quality-contract.test.mjs | Client contract and error-path tests |
| modules/quality/quality-demo.mjs | Volatile in-memory training engine and user personas |
| modules/quality/quality-demo.test.mjs | Fictitious stock/QC/FEFO/recall/security path tests |
| modules/quality/index.html | Interactive, no-network quality workbench |
| modules/quality/quality-workbench.mjs | Role/workflow-specific demo UI operations |
| modules/quality/quality.css | Responsive extensions to existing CORE10 owner-console style |

## Run and verify

- GitHub workflow: https://github.com/mistybari99/CORE-10-CENTRAL/actions/workflows/core10-a058-quality-ci.yml
- Node contracts: node --test modules/quality/quality-contract.test.mjs modules/quality/quality-demo.test.mjs
- Static workbench from repository root: python3 -m http.server 8000; open http://localhost:8000/modules/quality/index.html
- Disposable DB run order: first create synthetic authenticated/anon roles; next internal/enterprise-sql/c10_a018_demo_backend.sql; tests/c10_a018_demo_seed.sql; internal/enterprise-sql/c10_a018_inventory_v1.sql; internal/enterprise-sql/c10_a058_quality_lot_recall_v1.sql; tests/c10_a058_quality_e2e.sql.
- Test gates: exact-key retries, mismatched request replays, lot overdraw, bypass denial, quarantine sale refusal, release approval, expiry and FEFO, transfer conservation, genealogy cycle rejection, descendant recall, disposal and zero stock close, canonical stock reconciliation, unauthorized tenant/site/investor/revoked/anonymous access, protected journal writes and uncallable internal helper functions.

## What is and is not complete

This is a **large functionally built and tested isolated quality vertical slice**. It is **NOT** deployed or operationally certified. Synthetic SQL session claims are NOT real Supabase GoTrue user logins. The browser mock is NOT connected to the SQL database and its stock is not real. No real business, real customer data, real money, paid provider calls or production writes occur.

Important remaining release-gated integrations: production schema/backfill/rollback; signed JWT/GoTrue HTTP negatives; compatibility with A049 purchase/BOM/sale/return; true lot-to-customer distribution trace and recall notices; costing/COGS; tax; DR/backup; site-level performance; owner acceptance; Android and desktop live-browser QA. Critically, adding tracked stock guard to a live deployment without coordinating all stock handlers could cause valid operations to fail; keep it isolated until a reviewed migration.

Claude A055/CRM A057, Codex preview #60, Codex global research #67 remain untouched. Existing Master Decision Book remains the only governance record: https://docs.google.com/spreadsheets/d/1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs/edit. This README adds no new owner policy.
