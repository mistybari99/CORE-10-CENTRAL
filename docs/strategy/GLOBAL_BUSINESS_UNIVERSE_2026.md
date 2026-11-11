# CORE 10 Global Business Universe 2026

**Evidence date:** 2026-11-11. **Truth level:** research/specification, not implementation or legal certification. This is a representative global map, not an impossible census of every business.

## Operating models and canonical flow

CORE 10 must support B2C/D2C, B2B company-location accounts, wholesale/distribution/dealership, franchise, marketplace/B2B2C, subscription/preorder, project/contract, field service, rental, manufacturing/subcontracting, intercompany, agent/commission, agriculture and nonprofit/grant models. The reusable flow is:

`trigger → typed source document → scoped approval → domain event → stock/accounting/settlement effect → source-linked report → correction/reversal`

The commercial seller, inventory owner, physical custodian, fulfiller, invoice issuer, payment recipient and accounting entity are separate roles. A single `business_id` cannot safely collapse them for dropship, marketplace, franchise, consignment or intercompany work.

## Sector/workflow map

| Sector/model | Core workflow | Pack/adapter additions | Critical exceptions |
|---|---|---|---|
| Retail/wholesale | quote/order/POS → fulfil → invoice → settle → return | barcode, counter shift, price/promotion, channel mapping | oversell, split fulfilment, cash variance, no-receipt return |
| B2B/distribution | company-location account → quote → credit approval → delivery → AR | dealer programs, rebate/claim, territory | credit hold, sell-in vs sell-through, suspended location |
| Food/bakery | lot receipt → recipe batch → QC/release → transfer/sale | allergens, yield, expiry, recall | substitute lot, quarantine, waste, recall |
| Restaurant/cloud kitchen | order/check → KOT/KDS → serve/deliver → close | modifiers, table/session, rider/channel settlement | void after fire, split check, KDS outage |
| Paint/hardware | formula/shade → tint/QC → dealer sale | SDS/hazard adapter, PDC/cheque, principal scheme | retint, unsafe substitute, rebate dispute |
| Manufacturing | demand → plan → work order → issue → operations/QC → receipt | MES adapter, genealogy, capacity | rework, scrap, downtime, by-product, missing cost |
| Construction | bid/BOQ → commitment → site issue → progress acceptance → billing | BIM link, retention, change order | superseded drawing, disputed quantity, unapproved field work |
| Field service/maintenance | request → estimate/SLA → schedule/work order → evidence → invoice | asset history, meter, warranty | no access, repeat visit, emergency work, lockout |
| Import/export/3PL | contract → booking/documents → customs response → receipt/landed cost | country customs/LC/sanctions adapters | hold, demurrage, short shipment, amended documents |
| E-commerce/marketplace | listing/order webhook → reserve → fulfil → refund/reconcile | provider payout/fee adapter | replay, seller dispute, refund after payout |
| Rental/hospitality/real estate | reserve resource → dispatch/check-in/use → return/checkout | folio/night audit, lease, inspection | overbooking, damage, room move, early termination |
| Agriculture | field/season/activity → harvest lot → grade/aggregate → settlement | scheme/sustainability adapters | weather loss, mixed lots, offline producer capture |
| Nonprofit/NGO | award/restriction → budget/disbursement/expense → outcome report | IATI/donor export | restricted fund, in-kind gift, donor privacy |
| Healthcare/education/energy/public | ERP procurement/workforce/assets boundary | FHIR/OneRoster/CIM/statutory adapters | consent, safety, privacy, appeal; research-only initially |

## Daily roles and operational controls

The minimum role universe is tenant owner, business owner, site manager, cashier/counter staff, requester, buyer, approver, receiver/QC, warehouse worker, planner/operator, maintenance technician, accountant/treasurer, HR/payroll, auditor, investor/partner, customer/contractor, revoked/unassigned user, anonymous attacker and platform operator without implicit tenant-data access.

At a small shop, one person may hold multiple roles through an explicit owner-approved compensating control. At 303 sites, policy-bounded local execution and exception queues replace a global approval bottleneck. Requester, approver, receiver, invoice verifier and payer remain separable.

## Universal failure chains

1. **Offline sale:** capture bounded intent → reconnect → reauthorize → revalidate price/tax/stock/period → accept/conflict/reject → one idempotent effect.
2. **Payment uncertainty:** timeout becomes `UNKNOWN` → inquiry/callback reconciliation → one settlement; retry never duplicates money.
3. **Transfer:** dispatch reduces source available and creates in-transit; receipt increases target; never revenue.
4. **Return:** inspect disposition → source-linked credit/refund → only resellable quantity returns to available stock.
5. **Tax/FX correction:** preserve original policy/rate evidence → correction document → balanced journal; missing policy/rate is incomplete, not zero.
6. **Disaster restore:** encrypted manifest → isolated restore → counts, stock lineage, ledger balance and audit reconciliation → separately approved cutover.

## Small-business versus enterprise counterexamples

- One mutable price works at one counter but fails across 303 sites; use versioned effective policy.
- A franchise outlet may look like a branch but be a separate legal operator; tenancy and intercompany cannot be inferred from branding.
- A quantity-only item works for simple resale but fails for serialized rental assets, expiring food, recall and custody.
- A central owner queue may feel safe but collapses throughput; route routine work locally and surface exceptions centrally.
- A donation is not a sale, a transfer is not revenue, payroll approval is not payment, and marketplace collection is not automatically platform revenue.

## Primary evidence

- Microsoft procurement/approval: https://learn.microsoft.com/en-us/dynamics365/business-central/across-how-use-approval-workflows
- Oracle procurement lifecycle: https://docs.oracle.com/en/cloud/saas/procurement/26d/fapra/api-requisition-lifecycle-details.html
- Shopify B2B locations and purchase options: https://help.shopify.com/en/manual/b2b/getting-started/terminology and https://help.shopify.com/en/manual/products/purchase-options
- GS1 traceability: https://support.gs1.org/support/solutions/articles/43000734475-how-does-traceability-work-
- ISA-95 ERP/MES boundary: https://www.isa.org/standards-and-publications/isa-standards/isa-95-standard
- UN/CEFACT trade standards: https://unece.org/trade/uncefact/mainstandards
- FAO traceability: https://www.fao.org/food-safety/food-control-systems/traceability---recalls/en
- WCAG 2.2: https://www.w3.org/TR/WCAG22/

All were retrieved 2026-11-11. Bangladesh tax, payroll, customs, retention and regulated-sector rules remain region-policy validation required.
