# Master Plan Level 1 preview — source of Cloudflare release

This worker is a **synthetic, read-only** rebuilt preview sourced from Owner's Final Master Plan and the live Board checked on 2026-11-16. It replaces the old mixed Build01/02A/PR#100 snapshot in the existing `core10-central` Worker only. It does not claim to be the authenticated application.

- Canonical trunk as-of verification: `559879576a15a91d2472dc8c9f2dc6fb0439508d` (PR #106).
- NP01 PR #107 integrated into the trunk; B-020 unfinished.
- NP02 Owner Control Centre source exists but has no staging connection on this Worker.
- B-011/012 and NP03B/NP06/NP05A integration dependencies remain pending.
- No Supabase credentials, calls or database bindings; no Cloudflare Level 2 key.
- Exact worker source in `preview/clean-masterplan-level1.worker.mjs`; deployment is manually released to existing Worker `core10-central` only after owner request.
- Old worker release ID `15084307-6cd9-4956-94c2-5d60f3901465`; previous active version `b34943c8-b29a-417a-b75c-3908041862a9`. Restore using Cloudflare version history if necessary.
- Routes: `/`, `/app.css`, `/app.js`, `/health`; old mixed routes respond 410.
- Checks: no-store cache, restrictive CSP, NO DB, read-only GET/HEAD, explicit synthetic notices.

**No code from this branch is integrated into Claude trunk or main.** Kept Draft for review and provenance, not automatic merge. Future Level 2 requires separately explicit Owner approval, staged migration checks and signed E2E.
