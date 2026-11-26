# CORE10 clean signed-only release

Owner requested cleanup of old confusing live surfaces. Retain signed Home/Business, Master, Stock, Sales draft invoices, Control and Setup. Remove replay, fixture/workspace, old draft Sales, old Manufacturing and preview Approval routes from the active Worker allowlist. Preserve Git history and previous Worker rollback version. Unready Finance, PaperOps, Manufacturing UI, reviewer, staff and industry modules are not published as simulated workflows. Existing canonical backend migrations remain; no Auth user or business deletion. Existing modules keep their independent authorization and setup login; no universal SSO claim.

Build: `node apps/central/build-clean.mjs`; tests: `node --test tests/core10-clean-release.test.cjs`. Historical preview build/verifier remain unchanged for audit, not the clean deployment target. No direct DML or new SQL in this branch. Only exact signed routes, no fixture assets.
