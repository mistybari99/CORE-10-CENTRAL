# §7b.4 Shared signed shell context — first actual BUILD

Date: 2026-11-22. Board: B-040. From canonical trunk `0d15d405`.

- Shell sign-in uses the **existing** CORE10 staging publishable key + shared-origin Supabase Auth client and canonical signed `build01_context_v1`; **no new auth provider**.
- Authenticated Group > Business > Site selects only the server-authorized tenant, business and site cross-reference. Changing the dropdown re-reads the signed RPC. No tenant, site or role is guessed or persisted as permission.
- Strict response shape + actor match and account-switch guard, before/after `auth.getUser()` on every context fetch. Async responses are epoch-invalidated at sign-out/revocation. Embedded private iframe is cleared on shell sign-out.
- A scoped navigation selection **does not force itself into every module's internal business/site form**. Modules still run their own canonical Auth/Control checks on writes. Future integration can bind these selections only after independent module tests.
- Existing 11 hash routes, 390/1440, bn/en, draft-only banners and canonical page permissions stay intact. No staging SQL, business data edits, Form Engine, Finance, Sales, Claude Procurement or Cloudflare deploy.
- Full browser CI and synthetic actor/scope/revocation negatives must pass before integration. Real signed Owner acceptance remains a separate gate.
