# End-to-End Synthetic Demo Test Factory

**Implemented truth:** coded and local isolated tests pass. No database posting, real Auth, provider, deployment or production data.

## Reuse and provenance

`internal/demo-factory/index.js` imports the canonical A046 manifest rather than copying persona authority. Every build uses seed `CORE10-DEMO-2026-11-11`, schema `core10-global-demo-factory-v1` and a SHA-256 provenance digest. Reset/reseed means regenerate from the immutable seed; no mutable demo state is retained.

## Dataset

- 2 tenants and 16 referenced A046 personas.
- 6 synthetic businesses: sweets/bakery, paint/hardware, construction, restaurant, wholesale and technology/services.
- 4 functional sites compatible with the current A046 scope plus a separate 303-site structural fixture (101 sites for each primary business).
- Fictional supplier, customer, contractor, flour, sweet pack, paint and cement items; UOM conversions, lots and expiry examples.
- No emails, phone numbers, credentials, production identifiers or operational records.

## Golden chain

`requisition → PO → goods receipt → transfer → production → sale → return → customer receipt → supplier payment`

Expected math uses fictitious currency code `XTS` and minor units:

| Assertion | Expected |
|---|---:|
| transfer revenue | 0 |
| raw inventory ending | 130 kg |
| finished inventory ending | 65 units |
| net revenue | 63,000 |
| net COGS | 35,000 |
| gross margin | 28,000 |
| AR ending | 33,000 |
| AP ending | 150,000 |
| net cash change | -20,000 |

Eleven expected journal fixtures each satisfy DR=CR and reference a source document. They are independent expected math, **not posted/certified journals**.

## Negative cases

| ID | Case | Expected |
|---|---|---|
| DEMO-NEG-001 | negative stock | `inventory_insufficient` |
| DEMO-NEG-002 | same key, changed payload | `idempotency_conflict` |
| DEMO-NEG-003 | offline replay after revocation | denied and unposted |
| DEMO-NEG-004 | direct cross-tenant request | deny without disclosure |
| DEMO-NEG-005 | missing source cost | `INCOMPLETE_NOT_ZERO` |
| DEMO-NEG-006 | duplicate serial | deny |
| DEMO-NEG-007 | replay into closed period | deny and unposted |

## Test stages

1. Node determinism/provenance and expected-math validation — implemented.
2. Consumer adapters emitting A048/A049 commands into disposable PostgreSQL — next, after exact contract parity.
3. Local signed-HMAC PostgREST negative matrix — synthetic only.
4. Real nonproduction GoTrue two-tenant role matrix — not authorized/available, separate gate.
5. Browser 390/1440 task journey — after domain adapter; must show fixture/source/incomplete states.
6. 303-site performance measurement — separate from structural count; no capacity claim today.

## Commands

```text
node tests/demo-factory/core10-global-demo-factory.test.js
node tests/demo-factory/core10-capability-registry.test.js
node internal/demo-factory/index.js report
```

The dedicated workflow is `.github/workflows/core10-global-demo-factory.yml`.
