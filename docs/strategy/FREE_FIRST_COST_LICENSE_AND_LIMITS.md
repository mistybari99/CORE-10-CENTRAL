# Free-First Cost, License and Limits

**Checked:** 2026-11-11. No paid plan, provider or production service was enabled. Prices/quotas are volatile and must be rechecked before procurement.

| Layer | Free-first choice now | Limit / cost trigger | Replaceable path |
|---|---|---|---|
| source/CI | public GitHub repo and bounded GitHub Actions | public exposure; runner minutes/storage/concurrency policies; hosted runner outages | self-hosted runner or paid plan only with approval |
| runtime | local Node/browser fixtures; static/Worker preview | preview is not ERP backend; CPU/request/build quotas and domain needs | provider-neutral HTTP adapter; measured hosted tier later |
| database | PostgreSQL 17 disposable CI | no durability/Auth/SLA; hosted storage/compute/egress/backup limits | standard PostgreSQL migrations; approved managed tier later |
| auth | synthetic personas/local JWT contract tests | not GoTrue/real session/RLS proof | isolated nonproduction Supabase/Auth stage when authorized |
| object/docs | local deterministic fixtures | no durable tenant storage or OAuth | PR #27 provider port; Drive/S3-compatible adapters |
| backup | disposable `pg_dump`/restore CI | excludes production Auth/Storage/failure-domain/key recovery | encrypted external backup plus isolated restore drill |
| email/SMS | dry-run/no-op | per-message fees, consent, sender verification, regional regulation | PR #27 messaging adapters with caps/kill switch |
| payments | no live provider | processing/refund/chargeback/settlement fees | provider-neutral intent/reconciliation after explicit approval |
| maps/routing | none/local test data | request quotas, geocoding terms, privacy | optional adapter and cost meter |
| AI | local rules/advisory specs only | token/API spend, data privacy, nondeterminism | opt-in scoped tools; human confirmation; budget cap |
| monitoring | test logs and correlation IDs | retention/volume and tenant-data leakage | redacted provider-neutral sink |

## License observations

- PostgreSQL and Node enable an open, portable core. Dependencies still require individual license/SBOM review.
- ERPNext/Frappe, Dolibarr, Tryton, iDempiere and other open-source products show self-hostable options; open-source does not remove operations, security, backup, localization or support cost.
- Odoo Community/Enterprise boundaries, hosted Frappe, commercial retail/restaurant products and vendor marketplace modules must not be represented as universally free.
- Commercial suites (Microsoft, SAP, Oracle, NetSuite, Workday, Infor, IFS, Sage, Epicor, Acumatica, Salesforce) are benchmarks, not zero-cost dependencies.
- Payment processing, SMS, email delivery, domains, hardware, app marketplaces and professional statutory review are natural paid triggers.

## Cost-control contract

Every optional adapter records provider, plan/entitlement truth, region, API/version, quota window, observed usage, threshold alert, owner-approved budget, kill switch, data egress and replacement port. Hitting a quota must queue/fail visibly; it must never corrupt stock, journal or consent state.

## Scale honesty

The 303-site fixture proves deterministic structure only. Enterprise readiness requires measured authorization-query cost, stock lock contention, report latency, event backlog, browser payload, backup/restore time and provider throttling. “Built free” does not mean “free unlimited production.”

## Sources

- GitHub Actions billing: https://docs.github.com/en/billing/managing-billing-for-your-products/managing-billing-for-github-actions
- PostgreSQL license: https://www.postgresql.org/about/licence/
- Odoo pricing: https://www.odoo.com/pricing
- ERPNext pricing: https://frappe.io/erpnext/pricing
- Shopify pricing: https://www.shopify.com/pricing
- Square pricing: https://squareup.com/us/en/pricing
- Toast pricing: https://pos.toasttab.com/pricing

Retrieved 2026-11-11; numeric prices intentionally omitted because country, contract and packaging vary.
