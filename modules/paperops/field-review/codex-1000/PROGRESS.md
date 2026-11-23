# Codex original-source audit

| Batch | Fields | Findings | Exact audit CI |
|---|---:|---|---|
| A001 | 50 | 10 high, 2 medium | https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45114211289 |
| A002 | 50 | 9 high, 3 medium | https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45114521073 |
| A003 | 50 | 10 high, 1 medium | https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45115359303 |
| A004 | 50 | 8 high, 2 medium | https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45115730237 |
| A005 | 50 | 8 high, 2 medium | https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45116116749 |

A002 covers R-01:waste_qty through C-04:on_c. Both original C-04:who declarations are preserved under one manifest ID. Evidence commits for the two exact runs are 6349dc78039f52ec7a867d1f8c3fe9e38b78174d and 1778382a1a9bd48bbf83921570bec8f9cfc7353a.

A003 exact evidence commit: 62923049adeee394d72de527f4898be72599bd38. It covers C-04:on_d1 through C-05:over_credit, including three declarations each for C-06:amt and C-06:date.

A004 exact evidence commit: c5f0325e4fcd4cd3e938723e0c2110749e916e41. It covers C-05:over_party through R-02:decider_role.

A005 exact evidence commit: d12ccd24901b29bba8a96e9942d9fc4fa96600d0. It covers R-02:decided_by through S-06:inv_no.

A006 in progress. Static declarations for all 50 positions 251–300 are saved in A006-source-scan.json. Rule evidence, findings and fixtures are pending.

Full batch gates passed: 5/20. Remaining: 750 fields across A006–A020. Coordination Board / Decision Book: NOT WRITTEN.
