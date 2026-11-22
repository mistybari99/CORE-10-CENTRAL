# CORE-10 Central §7b.4 mobile navigation — isolated BUILD (2026-11-22)

Board: B-039. Branch: `build/chatgpt-central-mobile-nav-20261122`. Base: canonical trunk `327029db6b8715eceb25d7f504bd4651bae07cc3`.

## Actual code

- Existing **11** hash routes, frames, staging banners and draft Sales/Manufacturing labels preserved.
- Desktop sidebar grouped into Workspaces, Operations, Approval/Admin without introducing any new authorization rule.
- Mobile (≤760 px): 4 primary route links (Home/Business/Stock/Approvals) and an accessible **More** menu providing the other seven routes. Real route hash links, active-current indicators, click-outside and Escape close, bilingual labels.
- No Supabase client, authentication/session sharing or new CRUD was implemented; the signed module pages retain their existing sign-in isolation. Real **Group ▸ Business ▸ Site** switcher, role-specific homes, shared sign-in, design tokens and complete i18n dictionaries are the next independent slices.

## Verification / release boundary

- Source-contract + Chromium regression: `node --test tests/core10-central-mobile-nav.test.cjs` after `node apps/central/build.mjs`.
- Entire existing 56 local + 56 public Worker checks still run unchanged. Public Worker remains old release until separate release authorization.
- Historical §7b.3 byte-identity test retains *every assertion* and runs inside a detached worktree at exact PR #134 head `4345b6e4aa7ee593a455ee29dceccf55d61ade7f`; current candidate is tested separately rather than falsely expected to match original Worker SHA.
- No migration/DB, protected projects, old ERP, staging, live Cloudflare or `main` modifications. No Form Engine, NP03A 0207 Purchases, NP03B Sales, NP06 Finance or automation edits.
