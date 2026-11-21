# B-020 / 0110 — Submission, delegation and revoke Owner Control gate

Lane: NP01 ChatGPT, `build/chatgpt-np01`; fresh Draft PR after #107 integration.
Authoritative trunk: `ccr-15ed11dd-n3hw5h` at `559879576a15a91d2472dc8c9f2dc6fb0439508d`.

## What changed

- Three existing SECURITY DEFINER business RPCs are replaced, preserving signatures, Auth and idempotency:
  `submit_typed_approval_v1`, `delegate_approval_stage_v1`,
  `revoke_approval_delegation_v1`.
- Each directly calls `core10.control_check_v1(business,'gov002.review',NULL)` **after** its
  canonical Auth check and **before** replay or mutation. DISABLED must reject even an idempotent replay.
- In this post-0102 NP01 range, `core10._control_registry_promote_v1` promotes
  the exact three rows with `tests/migrations/np01-control-submit-delegation-e2e.sql`.
  Migration deliberately fails if promotion is not evidence-backed.
- Strict down migration demotes only those rows and restores the exact
  0014/0011 function bodies.
- Synthetic PG17 Owner/maker/business-owner/target-manager/foreign-owner
  fixtures: disabled/re-enabled, replay/duplication, same-tenant role,
  foreign-tenant forged JWT metadata, delegation revoke, canonical audit.

## Count and limits

With 0103/0106 existing promotions, the expected registry is
**6 enforced / 7 exempt / 8 pending** (assuming no new lanes add other RPCs).
The remaining `gov002.review` `configure_approval_route_v1` requires the
separate 0–5 stage-limit design and regression reconciliation: existing 2-,3-,5-stage
fixtures in one business cannot be silently made to obey an unrelated business-level
default of 1 stage. This increment **does not certify stage count** or source posting.
Six 0014/0015 threshold/exception APIs remain API-closed by 0017.
Setup and GOV003 remain pending. No 16-persona signed acceptance claimed.

No staging SQL, Cloudflare, production, IMG-ERP-SG, or cross-lane push.
