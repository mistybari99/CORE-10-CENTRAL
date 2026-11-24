# Codex original-source audit

| Batch | Fields | Findings | Exact audit CI |
|---|---:|---|---|
| A001 | 50 | 10 high, 2 medium | https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45114211289 |
| A002 | 50 | 9 high, 3 medium | https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45114521073 |
| A003 | 50 | 10 high, 1 medium | https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45115359303 |
| A004 | 50 | 8 high, 2 medium | https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45115730237 |
| A005 | 50 | 8 high, 2 medium | https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45116116749 |
| A006 | 50 | 5 high, 4 medium | https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45116892316 |
| A007 | 50 | 8 high, 1 medium open | https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45276544185 |
| A008 | 50 | 8 high, 2 medium | https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45277069689 |
| A009 | 50 | 6 high, 1 medium | https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45277459759 |
| A010 | 50 | 7 high | https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45277816442 |
| A011 | 50 | 6 high, 2 medium | https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45321255178 |
| A012 | 50 | 6 high, 1 medium | https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45321501676 |
| A013 | 50 | 7 high, 1 medium | https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45321679639 |

A002 covers R-01:waste_qty through C-04:on_c. Both original C-04:who declarations are preserved under one manifest ID. Evidence commits for the two exact runs are 6349dc78039f52ec7a867d1f8c3fe9e38b78174d and 1778382a1a9bd48bbf83921570bec8f9cfc7353a.

A003 exact evidence commit: 62923049adeee394d72de527f4898be72599bd38. It covers C-04:on_d1 through C-05:over_credit, including three declarations each for C-06:amt and C-06:date.

A004 exact evidence commit: c5f0325e4fcd4cd3e938723e0c2110749e916e41. It covers C-05:over_party through R-02:decider_role.

A005 exact evidence commit: d12ccd24901b29bba8a96e9942d9fc4fa96600d0. It covers R-02:decided_by through S-06:inv_no.

A006 exact evidence commit: 4dadc009fbed01db368689486e605b6d84bf2f8d. The 50 IDs extend from S-06:desc through S-04:c_bad.

A007 exact evidence commit: 2426f0f026af82c171fde9b2ba74637ccbce7212. Parent corrected slot 304 to R-01:cashier. A007-F001 is resolved as a source attribution correction.

A008 exact evidence commit: 0c3c5301a9f4c2dcbf271095cbb5ff49119b0157. It covers W-01:t_ret through P-01:rate_diff.

A009 exact evidence commit: 942bc729b6f08898f298fc0a96e001fddd26e478. It covers P-01:urgent_count through P-03:desc.

A010 exact evidence commit: 05ed405b43250171356ee474fa90a316d312ccc1. It covers P-03:unit through P-06:address.

A011 exact evidence commit: 7dcf669055a551d450e3409d264307f8b85a5e5b. It covers P-06:credit_days through S-01:deliv_mode.

A012 exact evidence commit: 6af57bfe2b950309f8d1c103818c3e47dfeaf8fa. It covers S-01:address through S-02:memo_no.

A013 exact evidence commit: fae37883d02ab395ed1a6b1d9b22b2b282f6798c. It covers S-02:item through S-03:deadline.

A014 covers S-03:in_worklist through M-01:found_time. Its exact-head CI is pending.

Full gates passed: 13/20. Coordination Board / Decision Book: NOT WRITTEN.
