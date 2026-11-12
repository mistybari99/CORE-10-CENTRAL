# CORE 10 Central — Build 05 Paint/Hardware isolated engine
Existing module: C10-CAP-PAINT-001 (MODULE DELIVERY sequence 19); D031 and REV-009.
Branch: feature/c10-build05-paint-tint-qc-quote-20261112
Integration owner: Codex, later. This is a DRAFT, not released.

## Implemented
- Immutable, business/tenant-scoped shade recipes, versioned pigment dosage in microlitres per litre, output SKU.
- 2.5-litre and other integer-volume tint tickets with expected doses and configured tolerance.
- Operator mix, separate checker QC, pass/fail, safe rework and evidence reference.
- Scoped append-only synthetic events, deterministic replay receipts, per-business operational report.
- Preview-only dealer price/rebate in integer minor currency units; tax and stock availability remain UNKNOWN, never defaulted to zero.
- Non-posting canonical sales proposal that explicitly requires signed authorization, canonical stock, finance/tax and approval before any live posting.

## NOT DONE
No real login, storage, signed backend scope/RLS, SQL, production workflows, stock movements, payment, financial journal, VAT filing, client quote or full paint industry certification. The supplied context mode is always synthetic-only, never an authentication mechanism. This package neither uses nor modifies any actual Islamia data, legacy paths or other Build01/02/03/04 files.

## How to test
node --test internal/industry-packs/paint-hardware-v1/core.test.mjs

## Codex integration / merge checklist
1. Hold Draft PR until reviewing Build01 #86, Build02 #93, Build03 #85, Build04 #94 and A048/A049/FIN-001 interfaces.
2. Retain this additive industry-pack directory; do not clone any stock, approval, ledger or identity backend.
3. Replace synthetic context with signed canonical backend actor/scope. Add real RLS positive/negative, revoke, concurrent retry tests.
4. Persist recipe versions/tickets/QC events/replay receipts in the single canonical audited transaction boundary.
5. Price source needs authority and version check; tax may not be assumed to be zero. Add real stock availability and sale/COGS/journal reconciliation only after integrating canonical services.
6. Add Business Workspace UI and configuration under existing permission policy. Independently verify staging/rollback before any deployment.
7. Record exact PR/head/CI and remaining blockers in the SAME Decision Book tabs MODULE DELIVERY, MODULE BUILD DETAIL, CHANGE LOG, AUDIT EVIDENCE. Keep status NOT_COMPLETE_PER_DETAIL.

No production deployment, main merge, SG migration or stock/finance posting from this branch.