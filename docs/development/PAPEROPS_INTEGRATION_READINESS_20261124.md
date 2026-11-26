# CORE-10-CENTRAL — PaperOps protected integration readiness (DRAFT / NO MERGE)

Date: 2026-11-24. This is an **isolated selective transfer**, not a protected trunk merge, application deployment, hosted migration apply, production posting, or Owner release acceptance.

## Exact repository inputs

| Input | Exact SHA / blob | Action |
|---|---|---|
| Canonical trunk `ccr-15ed11dd-n3hw5h` | `9510e19826654e50ae87158aa4dcdfd968a058aa` | Branch base. Keep every unrelated current trunk file, including Sales 0300–0305 |
| Combined PaperOps #151 | `43baefc8e270f4f81643f71204ddc480edd9c427` | Superseded as integration source by fully ported #154 |
| W02 signed registry Draft #152 | `073da5b3f2606f782f2e7f41aa629d5b54dfe192` | Included unchanged through #154 |
| Latest scoped Lane B Draft #154 | `2bb224dbf06dee6ca210963bfc2fd0312e9ba515` | Copy exactly `modules/paperops/` tree `e368ee6c818286a945ab758a4e406e08fbecdec3` |
| W02 numbered Draft `0211` | up Git blob `2c0837186d215a4a65f4a225058ce7a2ac574fd0`, down `858eacf61c13857782c4f64e6a2a6833e6ea1282` | Exact-byte draft transfer ONLY; no apply |
| Canonical PaperOps workflow | Git blob `a3cd68128304ef3c9288d5a104638937328240a3` | Exact-byte transfer. Head SHA checkout |
| `paperops-evidence-hardening.yml` | Stacked-branch-specific | **Excluded** because its base filter is not canonical trunk |
| Frozen legacy `legacy/islamia-erp/` | Existing canonical trunk | **Untouched**; original 463-file preservation guards remain |

The selective transfer does **not** copy Parent #132 root app files, older #149 ownership manifest, legacy loaders, preview or Worker files. The Parent A007 `R-01:cashier` and F-03 A019 `name/qty/unit` 920–922 survive in the precise #154 source tree. Codex A001–A020, 1,000 Codex + 246 ChatGPT distinct fields, original 11 functional gaps and 20 obligations remain accounted for.

## Automated integrated candidate verification

- New pinned bridge test `tests/paperops-trunk-port-integrity.test.cjs` checks source tree and SQL Git blobs, exact 1,246 ownership, A007 and A019, frozen F-03 shared helper three distinct contexts and preservation of canonical Sales 0300–0305.
- Existing `paperops-canonical-port.yml` runs all source-only/extractor checks, combined A001–A020 and Lane B controls, root live/legacy isolation and real disposable GoTrue/PostgREST signed W02/Stock/Control.
- `core10-s0-migrations-ci.yml` checks migration contracts and full PostgreSQL 17 up/down/up on this exact integration head. It tests *rehearsal* SQL, not hosted applicability.
- Required evidence after Actions: record exact branch HEAD, run IDs, failure/skip counts and corrected test results. If CI fails, fix in this isolated branch; **never disable guards**.

## Protected release gate — HOLD, not automatically cleared by green CI

1. **NP03A 0207–0210** have not landed in this canonical trunk snapshot; 0211 is a **draft reservation**, not permission to skip earlier 0207–0210. Trunk owner must reconcile other open NP03A work and next staging migration number before merge/hosted apply.
2. `w02_custody_snapshot_v1` is an evidence-only signed **read**. Trusted publication API, enrolled production keys/rotation/revocation, authentic physical actor proof and immutable accepted reversal still **NOT BUILT**. Existing registry fixtures insert through disposable DB owner only, not a published API.
3. 1,246 original fields have source records; only 79 Lane B fields link to local nonposting controls. **0 proven fully signed ERP field integrations; 0 Owner-accepted**. All 11 functional gaps and 20 obligations remain release-OPEN.
4. The existing canonical shell already has signed context for some routes. PaperOps is **NOT** wired to signed operational UI, cross-tenant Owner Control and end-to-end posting routes.
5. Before protected merge: integration owner's explicitly scoped GO, cross-lane exact-head code review, migration ordering and official Board reservation, independent signed security review and the current trunk SHA check. Before staging hosted write: separately approved go/no-go, backup, populated-data BEGIN/ROLLBACK rehearsal, ordered checksums and signed actor test. Before live deployment: another separate GO and end-user acceptance.

**Owner decision:** HOLD for trunk merge, hosted staging apply and live deployment until the above gates pass. Green disposable tests do not authorize a real Stock or Money transaction.

**Ownership and coordination:** This isolated branch is the ChatGPT PaperOps integrator's only changed branch. Do not reset/rebase or push original #132/#148/#149/#151/#152/#154 or canonical trunk. Board row `PAPEROPS-PORT-24` records this candidate.
