# CORE 10 — Scoped Owner Inbox Integration (Phase A)

## What was implemented in GitHub
- Added **core10-owner-inbox.js** as a shared, standalone read-only owner decision view.
- It mounts on CORE 10 Master Portfolio and on a selected Business Owner Home.
- Both screens call the **same future authenticated RPC** `core10_owner_inbox_v1(p_business_id, p_limit)`. `null` means master rollup; integer means that exact business.
- No legacy `needs_you_oldest`, `list_queue_counts` or raw table queries are used in this new view.
- No fabricated counts or approval actions. Missing RPC, mismatched business ID, unrecognized business IDs, duplicate request IDs or malformed response **fail closed** with an explanatory warning.
- Islamia CSS, ERP menus, legacy approvals and transaction processing are untouched.
- The display is **read-only** until real API verification. Existing legacy Owner Board & Approval modules remain separate and their cross-business scope is NOT certified.

## Expected server RPC response
```json
{
  "certified": true,
  "scope": "owner",
  "business_id": null,
  "items": [
    {
      "id": "entry:123",
      "business_id": 12,
      "request_type": "entry",
      "title": "Opening stock approval",
      "status": "pending",
      "created_at": "2026-11-09T10:00:00Z"
    }
  ]
}
```

For a business inbox, `business_id` in the root response and **every** row equals the requested business ID. For a master inbox, root `business_id` is null and each item identifies its source business. Response is capped at 40 visible records, and shows no fabricated total count.

## Critical security contract
- The RPC must derive caller identity from `auth.uid()`, not caller-supplied role flags.
- Only true master owner may request null/all-business scope.
- A business manager may later be allowed by role only through a different permission contract; this view is owner-only.
- The SQL must resolve every source row's business ID through authoritative mapping; **never** fall back to the first business or infer from name.
- The same canonical request must use the same ID across business and master views.
- Do not use elevated functions merely to bypass RLS. Explicitly audit SECURITY DEFINER/EXECUTE grants and all SQL it calls.
- Exclude legacy sources that cannot be mapped without ambiguity.
- Approval decision RPC will be separate and require server-side role, business, state-transition, atomic audit and idempotency validation; **no approve/reject UI has been enabled**.

## Required next step
Run the read-only `CORE10_APPROVAL_PREFLIGHT.sql` on the real Supabase project **kbuhnpqooycqbzrfejcs**, inspect source schemas and existing security, then design and test the RPC and its write-side decision endpoint in staging before enabling live. The currently connected Supabase account sees a different inactive project and cannot verify production.

## Acceptance tests
1. Owner on CORE 10 requests `p_business_id:null`; owner in Islamia requests Islamia ID; owner in Paint requests Paint ID.
2. Same source request ID is returned in appropriate business view and master view, never duplicated.
3. Staff session never triggers this RPC from frontend and cannot call it directly with valid or forged business ID.
4. Wrong business ID, missing mapping, missing API, revoked permissions and malformed responses show no approval data.
5. Old Islamia theme and current approval processing remain intact.
