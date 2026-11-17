-- NP06/B-013 0403: F3 integrity contracts layered on the unmodified 0402 migration.
-- Zero new money/party balances; no other builder's migration is changed.
-- Manual posted journals can be linked as manual evidence. An external invoice/bill
-- cannot be called verified until canonical source adapters provide attestation.
DO $dep$ BEGIN
 IF to_regclass('core10.finance_arap_links_v1') IS NULL
 OR to_regclass('core10.finance_arap_allocations_v1') IS NULL
 OR to_regclass('core10.finance_reversals_v1') IS NULL
 THEN RAISE EXCEPTION 'FIN_ARAP_INTEGRITY_DEPENDENCY_NOT_CONNECTED'; END IF;
END $dep$;

CREATE FUNCTION core10._finance_arap_source_integrity_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $body$
DECLARE j core10.finance_journals_v1%ROWTYPE;
BEGIN
 SELECT * INTO j FROM core10.finance_journals_v1 WHERE id=NEW.journal_id;
 IF NOT FOUND OR j.status<>'posted' OR j.tenant_id<>NEW.tenant_id
  OR j.business_id<>NEW.business_id
 THEN RAISE EXCEPTION 'FIN_ARAP_SOURCE_NOT_POSTED'; END IF;

 -- Existing Money post only proves that this journal was posted; it does NOT
 -- attest an upstream Sales invoice or Purchase bill. No invented integration.
 -- Only explicit Owner-governed manual evidence can be linked until real
 -- read-only canonical source validation adapters are delivered.
 IF j.source_domain<>'manual'
 THEN RAISE EXCEPTION 'FIN_ARAP_EXTERNAL_SOURCE_NOT_ATTESTED'; END IF;
 RETURN NEW;
END $body$;

CREATE TRIGGER finance_arap_source_integrity_v1
 BEFORE INSERT ON core10.finance_arap_links_v1 FOR EACH ROW
 EXECUTE FUNCTION core10._finance_arap_source_integrity_v1();

CREATE FUNCTION core10._finance_arap_reversal_allocation_guard_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $body$
BEGIN
 -- An allocated invoice/bill or an allocated payment cannot be reversed through
 -- 0401 until an explicit canonical deallocation/reconciliation adapter exists.
 -- Raising here rolls back the new reversal journal AND its Audit in one txn.
 IF EXISTS(
  SELECT 1 FROM core10.finance_arap_allocations_v1 a
  JOIN core10.finance_arap_links_v1 l ON l.id=a.link_id
  WHERE l.journal_id=NEW.original_journal_id
     OR a.payment_journal_id=NEW.original_journal_id
 ) THEN RAISE EXCEPTION 'FIN_ARAP_ALLOCATED_REVERSAL_NOT_CONNECTED'; END IF;
 RETURN NEW;
END $body$;

CREATE TRIGGER finance_arap_no_allocated_reversal_v1
 BEFORE INSERT ON core10.finance_reversals_v1 FOR EACH ROW
 EXECUTE FUNCTION core10._finance_arap_reversal_allocation_guard_v1();

-- Audit/source trace is derived from the SAME posted Money journal (both sides)
-- and the canonical NP02 party. It is NOT an invoice/bill mirror or posting API.
CREATE FUNCTION core10.finance_arap_trace_v1(p_link bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $body$
DECLARE l core10.finance_arap_links_v1%ROWTYPE;
 j core10.finance_journals_v1%ROWTYPE;
 v_party_code text; v_payment_refs jsonb;
BEGIN
 SELECT * INTO l FROM core10.finance_arap_links_v1 WHERE id=p_link;
 IF NOT FOUND OR core10.actor_uid() IS NULL
  OR NOT core10.can_see_business(l.tenant_id,l.business_id)
 THEN RAISE EXCEPTION 'FIN_ARAP_READ_DENIED'; END IF;
 SELECT * INTO j FROM core10.finance_journals_v1
  WHERE id=l.journal_id AND tenant_id=l.tenant_id AND business_id=l.business_id;
 IF NOT FOUND OR j.status<>'posted' THEN RAISE EXCEPTION 'FIN_ARAP_SOURCE_NOT_POSTED'; END IF;
 SELECT code INTO v_party_code FROM core10.master_parties_v1
  WHERE id=l.party_id AND business_id=l.business_id AND tenant_id=l.tenant_id;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'allocation_id',a.id,'amount',a.amount,
   'payment_journal_id',pay.id,'payment_source_domain',pay.source_domain,
   'payment_source_ref',pay.source_ref,'payment_effective_on',pay.effective_on,
   'payment_post_audit_event_id',pay.audit_event_id,
   'allocation_audit_event_id',a.audit_event_id
  ) ORDER BY a.id),'[]'::jsonb) INTO v_payment_refs
 FROM core10.finance_arap_allocations_v1 a
 JOIN core10.finance_journals_v1 pay ON pay.id=a.payment_journal_id
 WHERE a.link_id=l.id;
 RETURN jsonb_build_object(
  'link_id',l.id,'business_id',l.business_id,'kind',l.kind,
  'party_id',l.party_id,'party_code',v_party_code,
  'document_journal_id',j.id,
  'document_source_domain',j.source_domain,
  'document_source_ref',j.source_ref,
  'document_provenance','manual_posted_journal_not_external_invoice_attested',
  'document_post_audit_event_id',j.audit_event_id,
  'link_audit_event_id',l.audit_event_id,'currency',j.currency,
  'effective_on',j.effective_on,'due_on',l.due_on,
  'account_id',l.account_id,
  'posted_amount',core10._finance_arap_net_v1(
    j.id,l.account_id,CASE WHEN l.kind='ar' THEN 'debit' ELSE 'credit' END),
  'reversed',EXISTS(SELECT 1 FROM core10.finance_reversals_v1 r
                   WHERE r.original_journal_id=j.id),
  'payment_allocations',v_payment_refs
 );
END $body$;

REVOKE EXECUTE ON FUNCTION
 core10._finance_arap_source_integrity_v1(),
 core10._finance_arap_reversal_allocation_guard_v1(),
 core10.finance_arap_trace_v1(bigint) FROM PUBLIC,authenticated;
GRANT EXECUTE ON FUNCTION core10.finance_arap_trace_v1(bigint) TO authenticated;
