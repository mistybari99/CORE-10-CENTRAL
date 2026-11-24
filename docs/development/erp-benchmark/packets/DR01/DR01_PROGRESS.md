# DR01 progress — restartable checkpoint

| Field | Value |
|---|---|
| Packet / claim | DR01 / A01 — Board row `ERP-BENCH-DR01` (row 50, appended 2026-11-24, status CLAIMED → see Board for latest) |
| Agent | Claude (isolated research session) |
| Branch | `ccr-9903eb4d-j4foqo` (session-designated; fast-forwarded onto `research/erp-benchmark-20261124` @ `a8e271e0`). Draft PR into `research/erp-benchmark-20261124`. |
| Source SHAs | trunk `9510e19826654e50ae87158aa4dcdfd968a058aa` (unchanged vs baseline) · research `a8e271e09339efc9fc91bbd7edf71bb687e611f0` · main `c390529` · ERPNext `a6f54f9c88dcc24fdf3c59319f24cd9cd9aa91bd` · Frappe `fd94443a1c5ffe6f1ef0fc02436d62d9ceaa9917` · HRMS `46b389047bb12fb9c86c1300c3d7bfd5f897f171` |
| Product code | **NONE.** CI NOT RUN (docs only). No migration, staging write, deploy, merge, legacy or PaperOps edit. |
| External reads | Google Sheets/Docs (Decision Book, 520 sheet, Board, 4 docs); GitHub PR/issue/CI APIs; 1 read-only SELECT on CORE10 staging `core10.schema_migrations`. Protected projects `kbuhnpqooycqbzrfejcs` / `luoeyyngayxpqecuuijb` **not** accessed. |
| External writes | Board: one appended claim row. Nothing else. |

## Deliverables in this folder
| # | File | State |
|---|---|---|
| 1 | ORIGINAL_VISION.md | done (batch 1) |
| 2 | PRESERVATION_CROSSWALK.jsonl (2,116 rows) | done for all IDs found; 334/520 Details mapped at capability level, 186 at symbol level |
| 3 | SOURCE_INVENTORY.jsonl (348 rows) | done |
| 4 | ERP_COMPARISON.md | done (counterparts for all 34 CAP; MOD-01…MOD-11; BM-01…BM-06 specs) |
| 5 | DRAFT_RECOVERY_REGISTER.jsonl (142 PRs) | done; 2 rows NEEDS_REVIEW are #106 (the trunk PR) and #157 (the research PR), both by design |
| 6 | COMPETITIVE_ADVANTAGE_CANDIDATES.md | done (A1–A10) |
| 7 | REGISTRY_PROPOSED_DELTA.jsonl (28 updates + 12 candidates) | done; shared REGISTRY.json **not** edited |
| 8 | DR01_PROGRESS.md | this file |
| 9 | BUILD_RECOMMENDATIONS.md (WO-01…WO-13) | done; only WO-01 is BUILD_READY |
| — | reconciliation.json; tools/*.py | generated / reproducible |

## Reconciliation (from reconciliation.json)
| Set | Found | Unique | Duplicates | Mapped | Unmapped / gaps |
|---|---|---|---|---|---|
| Detail IDs (MODULE BUILD DETAIL = 520-sheet) | 520 | 520 | 0 | 520 to a destination (186 symbol-level, 334 capability-level) | 0 unmapped. 3 `needs_verification`; 7 audit-vs-trunk mismatches |
| Requirements R | 131 (R001–R130 + R124-IMPL-NOTE-01) | 131 | 0 | 129 via Detail, 1 via trace only | **R130** absent from REQUIREMENT TRACE and from Detail links (purpose covered by the 463-blob legacy proof) |
| Decisions D | 57 live + 6 archived (D016–D020, D026 via REV-001) | 63 | 0 | 21 linked to Details; 36 are policy/governance decisions | 0 lost |
| CAP / scope | 32 CAP + 2 scopes (SAAS-A024, SIMULATION-A025) | 34 | 0 | 34 | 0 |
| CHG | 61 (numbering CHG-001…111 has designed gaps) | 61 | 0 | 61 with current state | — |
| C10-A actions | 61 | 61 | 0 | sheet status only (not re-verified) | — |
| PaperOps field IDs | 1,246 (A 1,000 / B 246) | 1,246 | 0 | 1,246 form-level cross-link to a Detail ID | 0 field parity approved; 1,246 final_acceptance all false |
| Legacy blobs | 463 | — | — | 463/463 match manifest | — |

**Detail maturity today:**
- By maturity: 44 LIVE_STAGING · 39 STAGING · 170 TRUNK (15 numbered but not hosted + 155 engine files) · 75 DRAFT (open PR only) · 192 PLAN (181 no code + 11 legacy only).
- Certified per detail: **0**.
- Compared with the 2026-11-16 audit: 76 upgraded; 7 need verification.

**Disposition:** 49 PRESERVE · 198 RECOVER · 156 ADOPT_CANDIDATE · 92 DEFERRED · 13 INVESTIGATE · 12 ADVANTAGE_CANDIDATE.

## Completed batches
- **B1 (2026-11-24):** all sources acquired; full-ID crosswalk; PR containment scan of 142 PR heads against trunk (blob identity plus `c10_demo→core10` rename normalization); upstream pins and licences; key upstream functions inspected with line numbers; staging ledger and CI at head.

## Not done / partial (honest list)
1. 334 Details are mapped at capability level only. They need symbol-level confirmation (exact RPC/table/test per Detail).
2. Original **menus/routes/user actions** inventory of the frozen legacy app (`legacy/islamia-erp/nav.js`, `ia.js`, `index.html`, `v2/`), and the 11 live shell routes old→new map. **NOT DONE** (handed to DR03 B01 as well).
3. Decision Book sheets captured but not analysed: RESEARCH ARCHIVE (16 docs/52 chunks), SOURCE TRACE (116 A/B candidate rows), DISCUSSION LOG (37), AUDIT EVIDENCE (93), CHANGE LOG (128), AUDIT CYCLES/QUEUE, BUILD LEDGER, PLAN INDEX. D049 guide doc not read.
4. Feature-level verification that GOV-002 side PRs #78–#99 and A008 #40/#43/#69/#71 are fully ported (paths differ; only containment by migration names was checked).
5. 15 GitHub issues listed, not analysed (e.g. #53, #56, #57, #110).
6. Per-action (C10-A) status not re-verified.
7. No test, benchmark or upstream runtime was executed (research mode). All performance is NOT MEASURED.

## Blockers
None for continuing read-only research. Build items are blocked as listed in BUILD_RECOMMENDATIONS (Owner policy decisions; migration order 0301–0305 → 0207–0210 → 04xx/05xx).

## Next task (exact)
**DR01 batch 2.**
1. Legacy route/menu/action inventory from `legacy/islamia-erp` at trunk `9510e198` (read-only), mapped to the Detail IDs and live shell routes.
2. Symbol-level confirmation for the 334 capability-level Details, starting with P0 caps GOV-001, SETUP-001, MDM-001, PROC-001, INV-001, SALES-001, FIN-001.
3. Analyse SOURCE TRACE and RESEARCH ARCHIVE for IDs missing from the crosswalk.
4. Read the D049 guide.

Regenerate:
```
python3 -I tools/build_crosswalk.py SRC UP .
python3 -I tools/build_inventory.py SRC .
python3 -I tools/build_delta.py . ../../REGISTRY.json
```
SRC = fresh exports. Fetch the Decision Book and 520 sheet via the Sheets API into `decisionbook.json` / `detail520.json`. Get PR heads with `git fetch origin '+refs/pull/*/head:refs/remotes/pr/*'`. UP = blobless clones at the pinned SHAs.

## Agent result line (M04 format)
DR01/ERP-BENCH-DR01 | 2026-11-24 UTC | trunk 9510e198, research a8e271e0, ERPNext a6f54f9c…cd9aa91bd, Frappe fd94443a, HRMS 46b38904 | findings above + crosswalk | dispositions per row | files: packets/DR01/** only | tests: none run (docs only) | NOT MEASURED | commit/PR: see Board row | blockers: none for research | next: batch 2 as above | Board: ERP-BENCH-DR01
