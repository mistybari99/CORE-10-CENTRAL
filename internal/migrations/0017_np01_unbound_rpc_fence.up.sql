-- NP01 B-020 / 0017: temporary fail-closed boundary while Owner Control integration is pending.
-- 0014-0015 added API-callable VOLATILE functions that are not registered in the
-- B-010/0102 Owner Control catalog. Do not disable the registry gate to hide them.
-- Until a follow-on owner-approved binding/registry migration is integrated,
-- REVOKE direct authenticated execute to prevent ungoverned mutations.
-- These are DRAFT-only functions, not yet part of a certified hosted API.
-- Full feature binding and reenabling is a separate B-020 integration gate.
REVOKE EXECUTE ON FUNCTION
 core10.assess_approval_threshold_v1(bigint,jsonb),
 core10.assess_current_approval_threshold_v1(bigint,text,text,jsonb),
 core10.configure_approval_threshold_v1(bigint,text,text,numeric,integer,text),
 core10.request_approval_exception_v1(bigint,text,text,integer,text),
 core10.decide_approval_exception_v1(bigint,text,text),
 core10.withdraw_approval_exception_v1(bigint,text)
FROM PUBLIC, authenticated;
