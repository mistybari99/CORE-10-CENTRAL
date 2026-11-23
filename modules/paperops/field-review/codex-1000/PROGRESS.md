# Codex original-source audit

| Batch | Fields | Findings | Exact audit CI |
|---|---:|---|---|
| A001 | 50 | 10 high, 2 medium | https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45114211289 |
| A002 | 50 | 9 high, 3 medium | https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45114521073 |

A002 covers R-01:waste_qty through C-04:on_c. Both original C-04:who declarations are preserved under one manifest ID. Evidence commits for the two exact runs are 6349dc78039f52ec7a867d1f8c3fe9e38b78174d and 1778382a1a9bd48bbf83921570bec8f9cfc7353a.

A003 is in progress. The draft source scan contains 50 IDs across C-04, C-06 and C-05 with 54 declarations. C-06:amt and C-06:date each occur in receivable, payable and priority collections. Rule evidence, issues and fixtures remain in review. No A003 close or parity claim.

Full batch gates passed: 2/20. Remaining: 900 fields across A003–A020. Coordination Board / Decision Book: NOT WRITTEN.
