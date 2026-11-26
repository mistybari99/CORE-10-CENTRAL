# CORE10 NP01 — connected services, push cadence and deployment safety
Date: 2026-11-16
Owner request: keep Google Drive decisions and board current, push each completed work step to the authorized GitHub branch, and use connected Supabase and Cloudflare where safe.

## Connection verification (read-only)
- GitHub: `mistybari99/CORE-10-CENTRAL` accessible; ChatGPT write lane is **only** `build/chatgpt-np01`, with one Draft PR into Claude trunk `ccr-15ed11dd-n3hw5h`.
- Google Drive: canonical Master Decision Book and shared Coordination Board are readable/writable. Record decisions in Book, implementation evidence in Change Log, and task status in Board.
- Supabase: connector is authenticated; the **only discoverable project** is `IMG-ERP-SG` (healthy PostgreSQL 17), which is D051 protected legacy. **Not a CORE10 staging database**. This check is NOT authorization to migrate, update, seed or deploy to it.
- Cloudflare: connector is authenticated; the account has an existing Worker named `trillionaire-me` and **no Pages projects returned** on the read-only list. No evidence links that Worker to the new CORE10 line. **Do not overwrite it** or create a production route as a shortcut.
- These are connector inventory observations, not acceptance or environment certification.

## DEC-10 — push + evidence after each meaningful work step
1. Before starting, read the board; claim the exact task and reserved migration block.
2. Write code/tests only to the lane's authorized branch. Push a commit at the end of **each** completed work step (and never hold more than two to four substantial unpushed changes).
3. Run required exact-head CI, including disposable PostgreSQL up/down/up and relevant negative checks. Red CI is repaired, never skipped.
4. Same work step: put pushed SHA, PR link, CI proof and outstanding blockers in the board. Record material decisions in the canonical Decision Book; append dated implementation evidence in its Change Log. Verify each record by readback.
5. Keep the lane PR Draft until all relevant rows are `READY_FOR_INTEGRATION`, DEC-08 Owner Control port is bound and the trunk owner has checked the merge. Only Claude pushes to trunk.
6. After two to four **integrated** substantial pieces, offer a Bangla Owner preview documenting what is real/synthetic.

## Target-specific deployments are a different action, not ordinary Git push
- **Supabase SQL / schema / Edge Functions:** no write to `IMG-ERP-SG`, `public` legacy schema, production or protected data. For signed staging, select or create a separate CORE10 staging project containing synthetic test data, complete the cost/ownership check, obtain a scoped Owner GO, verify migrations, then apply only to that exact staging target. Never use automatic promotion to production.
- **Cloudflare Pages / Workers:** identify an explicitly approved CORE10 project + branch + preview level before release. A new preview deployment needs Owner's one-time GO for that level, per protocol DEC-10. Existing unrelated Worker cannot be repurposed without explicit review.
- **Level 1** preview is synthetic click-through, no login or DB. **Level 2** is signed Owner ID backed by a separate synthetic staging DB, never IMG-ERP-SG.
- Never save credentials, JWTs, API tokens, database passwords or service role keys in GitHub, Drive or the board. Never claim live readiness from synthetic CI.
- Do not touch `main`, the existing protected legacy UI/data/URLs, or release/deploy routes without the separate target-specific authorization required by D051/D054 and the coordination protocol.

## Current handoff
- Existing Draft PR: https://github.com/mistybari99/CORE-10-CENTRAL/pull/107
- Board: https://docs.google.com/spreadsheets/d/1QyBpRr6rybexMwSA1ivLmn_VidrntbcOTRK4qi1c9Mc/edit
- Decision Book: https://docs.google.com/spreadsheets/d/1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs/edit
- B-005 is READY_FOR_INTEGRATION; B-006..B-008 are IN_PROGRESS, not deployed. DEC-08 Control-port binding and real signed staging proof remain blockers.
