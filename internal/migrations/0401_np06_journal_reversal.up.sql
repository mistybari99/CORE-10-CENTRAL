-- NP06/B-013/0401: immutable, source-linked reversal on the SINGLE canonical Finance journal.
-- No alternate balance, approval, audit, stock or permission engine. No hosted apply.
-- Reversals are a new equal-and-opposite posted journal in an explicitly open period.
-- Depends on 0400. Default Owner Control for reversal is OFF; posting still fails
-- closed for nonzero approval stages until the canonical GOV-002 adapter exists.
DO $dep$ BEGIN
 IF to_regclass('core10.finance_journals_v1') IS NULL
   OR to_regprocedure('core10.finance_post_journal_v1(bigint,text)') IS NULL
 THEN RAISE EXCEPTION 'FIN_REVERSAL_DEPENDENCY_NOT_CONNECTED'; END IF;
END $dep$;

INSERT INTO core10.control_catalog_v1
 (feature_key,title_en,title_bn,pack,default_enabled,default_stages,max_stages,
  allow_site_scope,approval_domain,approval_action,params) VALUES
 ('finance.journal_reverse','Reverse a posted Finance journal','পোস্টকৃত জার্নাল বিপরীত এন্ট্রি','NP06',
  false,0,0,true,NULL,NULL,'{}');

CREATE TABLE core10.finance_reversals_v1 (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 original_journal_id bigint NOT NULL UNIQUE,
 reversal_journal_id bigint NOT NULL UNIQUE,
 effective_on date NOT NULL,
 reason_code text NOT NULL CHECK(reason_code ~ '^[a-z][a-z0-9_]{2,40}$'),
 request_key text NOT NULL CHECK(request_key ~ '^[A-Za-z0-9_-]{8,128}$'),
 created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 audit_event_id bigint NOT NULL REFERENCES core10.canonical_audit_events_v1(id),
 UNIQUE(business_id,request_key),
 FOREIGN KEY(original_journal_id,tenant_id,business_id)
  REFERENCES core10.finance_journals_v1(id,tenant_id,business_id),
 FOREIGN KEY(reversal_journal_id,tenant_id,business_id)
  REFERENCES core10.finance_journals_v1(id,tenant_id,business_id)
);
ALTER TABLE core10.finance_reversals_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY finance_reversals_read_v1 ON core10.finance_reversals_v1 FOR SELECT TO authenticated
 USING(core10.can_see_business(tenant_id,business_id));
REVOKE ALL ON core10.finance_reversals_v1 FROM PUBLIC,authenticated;
GRANT SELECT ON core10.finance_reversals_v1 TO authenticated;

-- Reversal evidence cannot be modified, deleted or truncated even by accidental
-- privileged SQL; correction must be a new, separately governed transaction.
CREATE FUNCTION core10._finance_reversal_immutable_v1() RETURNS trigger
 LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $body$
BEGIN
 RAISE EXCEPTION 'FIN_REVERSAL_IMMUTABLE';
END $body$;
CREATE TRIGGER finance_reversals_update_delete_guard_v1
 BEFORE UPDATE OR DELETE ON core10.finance_reversals_v1
 FOR EACH ROW EXECUTE FUNCTION core10._finance_reversal_immutable_v1();
CREATE TRIGGER finance_reversals_truncate_guard_v1
 BEFORE TRUNCATE ON core10.finance_reversals_v1
 FOR EACH STATEMENT EXECUTE FUNCTION core10._finance_reversal_immutable_v1();
REVOKE EXECUTE ON FUNCTION core10._finance_reversal_immutable_v1() FROM PUBLIC,authenticated;

CREATE FUNCTION core10.finance_reverse_posted_journal_v1(
 p_original bigint,p_effective_on date,p_reason text,p_key text
) RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $body$
DECLARE
 j core10.finance_journals_v1%ROWTYPE;
 prior record;
 v_actor uuid:=core10.actor_uid();
 v_lines jsonb;
 v_reverse bigint;
 v_receipt bigint;
 v_draft_key text;
 v_post_key text;
BEGIN
 -- FOR UPDATE serializes competing reversals of the same posted source.
 -- Locked original is never updated or deleted.
 SELECT * INTO j FROM core10.finance_journals_v1 WHERE id=p_original FOR UPDATE;
 IF NOT FOUND OR v_actor IS NULL OR NOT core10.can_manage(j.tenant_id,j.business_id)
 THEN RAISE EXCEPTION 'FIN_AUTH_DENIED'; END IF;
 -- The Owner's reversal switch is independent of the existing draft,
 -- validation, post and period checks, all of which remain mandatory.
 PERFORM core10.control_check_v1(j.business_id,'finance.journal_reverse',j.site_id);
 IF p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
   OR p_reason IS NULL OR p_reason !~ '^[a-z][a-z0-9_]{2,40}$'
   OR p_effective_on IS NULL
 THEN RAISE EXCEPTION 'FIN_REVERSAL_INVALID_INPUT'; END IF;
 IF j.status<>'posted' OR j.audit_event_id IS NULL
 THEN RAISE EXCEPTION 'FIN_REVERSAL_REQUIRES_POSTED'; END IF;
 IF j.source_domain='finance_reversal' OR EXISTS
   (SELECT 1 FROM core10.finance_reversals_v1 WHERE reversal_journal_id=j.id)
 THEN RAISE EXCEPTION 'FIN_REVERSAL_CHAIN_DENIED'; END IF;

 SELECT r.original_journal_id,r.reversal_journal_id,r.effective_on,r.reason_code,
        r.request_key,r.created_by INTO prior
 FROM core10.finance_reversals_v1 r WHERE r.original_journal_id=j.id;
 IF FOUND THEN
  IF prior.request_key=p_key AND prior.reason_code=p_reason
     AND prior.effective_on=p_effective_on AND prior.created_by=v_actor
  THEN RETURN prior.reversal_journal_id; END IF;
  RAISE EXCEPTION 'FIN_ALREADY_REVERSED';
 END IF;
 IF EXISTS (SELECT 1 FROM core10.finance_reversals_v1 r
            WHERE r.business_id=j.business_id AND r.request_key=p_key)
 THEN RAISE EXCEPTION 'FIN_IDEMPOTENCY_CONFLICT'; END IF;
 IF p_effective_on<j.effective_on THEN RAISE EXCEPTION 'FIN_REVERSAL_BACKDATE'; END IF;
 SELECT jsonb_agg(jsonb_build_object(
   'account_id',l.account_id,
   'side',CASE WHEN l.side='debit' THEN 'credit' ELSE 'debit' END,
   'amount',l.amount,
   'memo','Reversal of journal '||j.id||' line '||l.line_no
  ) ORDER BY l.line_no)
 INTO v_lines FROM core10.finance_journal_lines_v1 l WHERE l.journal_id=j.id;
 IF v_lines IS NULL OR jsonb_array_length(v_lines)<2
 THEN RAISE EXCEPTION 'FIN_REVERSAL_LINES_MISSING'; END IF;

 -- Reuse the canonical Money port end to end: account/scope checks, balanced
 -- validation, Owner Control, GOV-002 fail-closed stages, max amount, period
 -- lock and canonical immutable audit receipt. Any denial rolls back the
 -- draft + validation + post as one database transaction.
 v_draft_key:=encode(sha256(convert_to('finance:reversal:draft:'||j.business_id||':'||j.id||':'||p_key,'UTF8')),'hex');
 v_post_key:=encode(sha256(convert_to('finance:reversal:post:'||j.business_id||':'||j.id||':'||p_key,'UTF8')),'hex');
 v_reverse:=core10.finance_draft_journal_v1(
   j.business_id,j.site_id,j.currency,p_effective_on,
   'finance_reversal','journal-'||j.id,v_draft_key,v_lines);
 PERFORM core10.finance_validate_journal_v1(v_reverse);
 PERFORM core10.finance_post_journal_v1(v_reverse,v_post_key);
 v_receipt:=core10._append_canonical_audit_v1(
   j.tenant_id,j.business_id,'finance','journal:'||j.id||':reverse',
   'finance.journal_reverse',v_actor,'finance:journal:'||j.id||':reverse',
   jsonb_build_object('original_journal_id',j.id,'reversal_journal_id',v_reverse,
    'effective_on',p_effective_on,'reason_code',p_reason,'request_key',p_key));
 INSERT INTO core10.finance_reversals_v1(
   tenant_id,business_id,original_journal_id,reversal_journal_id,
   effective_on,reason_code,request_key,created_by,audit_event_id)
 VALUES(j.tenant_id,j.business_id,j.id,v_reverse,p_effective_on,
   p_reason,p_key,v_actor,v_receipt);
 RETURN v_reverse;
END $body$;

INSERT INTO core10.control_rpc_map_v1
 (rpc_name,status,feature_key,reason,lane,board_row,test_ref)
 VALUES('finance_reverse_posted_journal_v1','enforced','finance.journal_reverse',
 'Owner-only reversal switch plus canonical draft/validate/post and immutable audit',
 'ChatGPT','B-013','tests/migrations/np06-finance-reversal-e2e.sql');

REVOKE EXECUTE ON FUNCTION
 core10.finance_reverse_posted_journal_v1(bigint,date,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION
 core10.finance_reverse_posted_journal_v1(bigint,date,text,text) TO authenticated;
