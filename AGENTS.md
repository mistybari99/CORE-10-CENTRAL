# CORE-10-CENTRAL — Agent Instructions (Preview Development Branch)

This file provides a **minimal Codex/Claude/GPT engineering entrypoint** for the one existing CORE-10-CENTRAL repository. It is not a second Owner Decision Book.

## Start here (mandatory)
- Read \`docs/development/CODEX_MASTER_EXECUTION_HANDOVER_2026-11-11.md\` in full.
- Read latest \`docs/development/CURRENT_HANDOFF.md\` on \`feature/c10-a018-foundation-catalog-v1\`; do **not** assume that file exists on \`main\`.
- Read GitHub latest repo/main/branch/PR/action evidence; inspect the single Master Decision Book at https://docs.google.com/spreadsheets/d/1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs/edit and D049 guide at https://docs.google.com/document/d/1VNB-ub0V49fg1QAPqyALk-1P79eqgbHJZwAdbq5-mCg/edit if access is available. If not, explicitly mark \`NOT VERIFIED\` instead of guessing.
- The **latest explicit Owner directive** and approved D033/D045/D046/D047/D048/D049/D050, R123–R129, REV-009 prevail; preserve older approvals.

## Mandatory Owner-approved language contract — ALL future ERP UI work

**C10-A064 / 2026-11-13:** Read [the single language contract](docs/ux/C10_LANGUAGE_CONTRACT.md) and [the detailed glossary](docs/ux/C10_BN_FIRST_GLOSSARY.md) before editing *any* CORE 10 CENTRAL user-visible page, app, module, demo, dialog, tooltip, report UI, or onboarding, including work delegated to Claude/Codex/other agents. This is an ERP-wide ongoing requirement, not a one-off Preview aesthetic and not a new ERP.

- Always offer exactly **Bengali / Eng/Bng / English**. Default **Bengali** (`bn-BD`): fluent Bangladesh Bangla in Bangla script, with common everyday loanwords written **স্টক, প্ল্যান, সেলস, রিপোর্ট, সেটিংস**; don't force artificial `মজুদ` or `পরিকল্পনা` in ordinary shop/business interface copy.
- **Eng/Bng** (`bn-BD-mixed`): same fluent Bengali sentence structure with commonly understood English words in Latin letters, e.g. **Stock-এর হিসাব মিলিয়ে নিন**, **নতুন Plan তৈরি করুন**. **English** (`en`) is natural English throughout. Keep terms in their culturally familiar style; no heavy transliteration or dictionary-like copy.
- All new visible UI text must be registered under a **semantic named translation key with reviewed copy for all three modes**, shared through the same canonical i18n adapter. Don't create each module's own competing locale engine, copy auto-translator, or hardcoded English-only labels. Technical identifiers, tenant IDs, permission codes, formulas and numbers remain unchanged.
- The initial implementation is `preview/i18n.mjs` on C10-A064 Draft PR #103. **It is a Preview-only adapter and currently not deployed**. Future signed/production UI modules must integrate the shared 3-mode contract through an appropriately scoped approved adapter; do not misrepresent Preview-only work as complete ERP localization.
- For every PR with user-facing changes, review all three modes at Android/mobile 390px and desktop 1440px. Run `node scripts/verify-language-contract.mjs` and the relevant UI/safety tests, state gaps honestly. No main merge, production deployment, real access/data writes without the existing Owner release gates.
- If an agent or a new chat lacks the latest code/docs, first **read these repo files and the single Master Decision Book**, rather than asking the Owner to repeat the vocabulary. Changing this contract requires a new explicit Owner decision recorded in the same Decision Book.

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


## Claude 3-package parallel build reservation (2026-11-11; coordination only)
The Owner reserved THREE Draft-only Claude packages in [the exact three-build instructions](docs/development/CLAUDE_THREE_BUILD_ASSIGNMENTS_2026-11-11.md): **A055** finish existing assets/maintenance PR #59 (CI currently failed); **A052** Owner Intent-to-Capability/Explainability Engine (Issue #53); **A053+A054** A046/A050/A051 workforce/portfolio + configurable payroll governance (Issues #56/#57). No shared-source edits or blind merges; each owns separate namespaced files and tests.
**Codex's next new task is NOT specified yet.** Codex should be aware of these reserved Claude namespaces but should not automatically start these packages, change Claude-owned branches, or merge pending PRs. The Owner will issue new Codex directions later. Existing preview-first source and production gates remain.
