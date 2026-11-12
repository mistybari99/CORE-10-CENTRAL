# GOV-002 — Signed review session integrity and fail-closed UI

This standalone Build 02 slice keeps the existing Supabase signed adapter and canonical PostgreSQL RPCs/RLS unchanged. It adds a session-bound facade around already-authorized review calls. Each read, mutation and export is bound to one signed user ID for this mounted workspace; `getUser()` before and after an underlying operation and an Auth state-change event listener prevent a stale result from another user appearing in the current UI.

**Behavior:** signed-out/changed-user/auth-error invalidates the workspace once, clears any visible approval/exception/activity data and shows a simple Bangla explanation. Any in-flight response is discarded, including a delayed paged read or decision receipt. The guard unsubscribes when the workspace is destroyed; same-user token refresh does not unnecessarily invalidate it. No RPC retry is performed for writes, so idempotency remains server-owned.

**Evidence:** independent Node tests simulate read, confirmed mutation and CSV export, account switching, missing subscription, signed-out in-flight response and cleanup. A real local Chromium browser uses a synthetic Supabase shim to verify 390/1440 DOM clearing. No actual GoTrue login is used in these tests.

**Security limitation:** a browser guard cannot reverse a command already accepted by a real server before logout. A034's owner/approval-specific explicit deny, permission expiry/revoke and GoTrue session checks MUST be implemented/verified on the backend; front-end callback does not grant any authority. No production Supabase, original Islamia ERP, Codex Build01, Claude GOV003, deployment or original theme are modified.

**UI/copy:** retain the existing mobile/desktop design and Bangladesh-language controls. Authentication error copy is concise and avoids raw SQL messages. 12ui hosted CLI was attempted but could not be installed in this environment; no 12ui pixel-perfect visual design output is claimed.