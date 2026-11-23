# Codex original-source audit

| Batch | Fields | Findings | Exact audit CI |
|---|---:|---|---|
| A001 | 50 | 10 high, 2 medium | https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45114211289 |
| A002 | 50 | 9 high, 3 medium | https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45114521073 |
| A003 | 50 | 10 high, 1 medium | https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45115359303 |

A002 covers R-01:waste_qty through C-04:on_c. Both original C-04:who declarations are preserved under one manifest ID. Evidence commits for the two exact runs are 6349dc78039f52ec7a867d1f8c3fe9e38b78174d and 1778382a1a9bd48bbf83921570bec8f9cfc7353a.

A003 exact evidence commit: 62923049adeee394d72de527f4898be72599bd38. It covers C-04:on_d1 through C-05:over_credit, including three declarations each for C-06:amt and C-06:date.

A004 started from manifest positions 151–200. Its draft scan has 50 original declarations from C-05:over_party through R-02:decider_role. Formula, warning and fixture review remains open.

Full batch gates passed: 3/20. Remaining: 850 fields across A004–A020. Coordination Board / Decision Book: NOT WRITTEN.
