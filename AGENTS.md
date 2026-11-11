# CORE-10-CENTRAL — Agent Instructions (Preview Development Branch)

This file provides a **minimal Codex/Claude/GPT engineering entrypoint** for the one existing CORE-10-CENTRAL repository. It is not a second Owner Decision Book.

## Start here (mandatory)
- Read \`docs/development/CODEX_MASTER_EXECUTION_HANDOVER_2026-11-11.md\` in full.
- Read latest \`docs/development/CURRENT_HANDOFF.md\` on \`feature/c10-a018-foundation-catalog-v1\`; do **not** assume that file exists on \`main\`.
- Read GitHub latest repo/main/branch/PR/action evidence; inspect the single Master Decision Book at https://docs.google.com/spreadsheets/d/1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs/edit and D049 guide at https://docs.google.com/document/d/1VNB-ub0V49fg1QAPqyALk-1P79eqgbHJZwAdbq5-mCg/edit if access is available. If not, explicitly mark \`NOT VERIFIED\` instead of guessing.
- The **latest explicit Owner directive** and approved D033/D045/D046/D047/D048/D049/D050, R123–R129, REV-009 prevail; preserve older approvals.

## Execute: code + tests, not speculation
- **Immediate priority:** verified first physical Preview V1 for Owner inspection. Existing branch \`preview/c10-integrated-20261111-v1\`, Draft PR #60, deployed **synthetic** public URL https://core10-central-preview-v1.mistybari99.workers.dev/.
- This preview contains assembled source of A045–A051, but ONLY A045 original in-memory Workshop demo is an explicitly runnable original backend fixture; other visual examples are synthetic until real signed staging. Do not claim complete ERP integration from source assembly.
- Make branch-safe actual code changes and relevant tests, commit them, and maintain Draft PR evidence. Display precise blocked/working distinctions.
- Reuse authoritative existing A018/A021/A034 identity and permissions, A048 stock command/ledger and A049 business transaction contracts; never clone old customized Islamia ERP as generic source. Business sites and brand/workflows are scoped and tenant-isolated.
- For meaningful UI: desktop and Android responsive, accessible, contextual guidance and formula/report destinations. No inert buttons disguised as working functions.
- Use PostgreSQL17 disposable and signed-API negative tests, Node tests, browser 390px/1440px and public HTTP smoke where relevant. CI must match exact SHA. GoTrue/real staging is **not** interchangeable with synthetic HMAC JWT.
- If parallel agents are available, partition independent files/modules, especially preserve Claude's A055 ownership; one integration lead for shared contract.

## Hard gates
- **Do not merge to \`main\` without explicit Owner approval.**
- **Do not apply production Supabase / IMG-ERP-SG SQL/RLS/schema migration or write real stock, money, payroll, accounts, users without Owner-approved independent release gate.**
- No fake successful payment/COGS/accounting result, fabricated deployed URL, invented statutory rate, tenant cross-scope exposure, unreviewed secrets, arbitrary engine code execution or hidden authorizations.
- Freeze source preservation of Islamia items/locations/history and customized reports (REV-009).
- Do not create alternate master ledgers, duplicated permission/transaction systems, or new ERP repos.
- External commercialization A024 and simulation A025 are deferred; keep scope in Owner's review order.

## Report in concise Bangla
Action+Decision ID / committed file paths & SHA / tests and CI PASS-FAIL-NOT-RUN / Draft PR / preview URL / what is working vs synthetic / Decision Book exact row updated or NOT WRITTEN / blocker + next executable step. No endless research loop.
