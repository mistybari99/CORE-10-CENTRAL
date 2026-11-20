-- NP01 B-020 / 0017 rollback: restore exactly the authenticated EXECUTE
-- permissions originally granted by 0014-0015 (PUBLIC still denied).
GRANT EXECUTE ON FUNCTION
 core10.assess_approval_threshold_v1(bigint,jsonb),
 core10.assess_current_approval_threshold_v1(bigint,text,text,jsonb),
 core10.configure_approval_threshold_v1(bigint,text,text,numeric,integer,text),
 core10.request_approval_exception_v1(bigint,text,text,integer,text),
 core10.decide_approval_exception_v1(bigint,text,text),
 core10.withdraw_approval_exception_v1(bigint,text)
TO authenticated;
