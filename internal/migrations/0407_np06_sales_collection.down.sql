-- 0407 cannot be removed after a real cash journal or allocation exists.
DO $guard$ BEGIN
 IF EXISTS(SELECT 1 FROM core10.finance_sales_collections_v1)
 OR EXISTS(SELECT 1 FROM core10.finance_journals_v1
 WHERE source_domain='sales_collection')
 OR EXISTS(SELECT 1 FROM core10.canonical_audit_events_v1
 WHERE action='sales.collection_posted')
 OR EXISTS(SELECT 1 FROM core10.control_setting_versions_v1
 WHERE feature_key='finance.sales_collection')
 OR EXISTS(SELECT 1 FROM core10.control_overrides_v1
 WHERE feature_key='finance.sales_collection')
 THEN RAISE EXCEPTION 'FIN_SALES_COLLECTION_ROLLBACK_DENIED_HISTORY'; END IF;
END $guard$;
DROP TRIGGER finance_sales_no_reverse_v1 ON core10.finance_reversals_v1;
DROP FUNCTION core10._finance_sales_no_reverse_v1();
REVOKE EXECUTE ON FUNCTION core10.finance_collect_sales_invoice_v1(
 bigint,bigint,date,numeric,text) FROM PUBLIC,authenticated;
DROP FUNCTION core10.finance_collect_sales_invoice_v1(bigint,bigint,date,numeric,text);
DELETE FROM core10.control_rpc_map_v1
 WHERE rpc_name='finance_collect_sales_invoice_v1'
 AND lane='ChatGPT' AND board_row='B-013';
-- Restore original F3 manual-only settlement integrity and derived Audit trace.
CREATE OR REPLACE FUNCTION core10._finance_arap_settlement_integrity_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $body$
DECLARE l core10.finance_arap_links_v1%ROWTYPE;
 pay core10.finance_journals_v1%ROWTYPE;
 v_side text; v_control_total numeric; v_asset_total numeric;
BEGIN
 SELECT * INTO l FROM core10.finance_arap_links_v1 WHERE id=NEW.link_id;
 SELECT * INTO pay FROM core10.finance_journals_v1 WHERE id=NEW.payment_journal_id;
 IF l.id IS NULL OR pay.id IS NULL OR pay.status<>'posted'
  OR pay.business_id<>l.business_id OR pay.tenant_id<>l.tenant_id
 THEN RAISE EXCEPTION 'FIN_ARAP_PAYMENT_SOURCE_NOT_POSTED'; END IF;
 IF pay.source_domain<>'manual'
 THEN RAISE EXCEPTION 'FIN_ARAP_PAYMENT_SOURCE_NOT_ATTESTED'; END IF;

 v_side:=CASE WHEN l.kind='ar' THEN 'debit' ELSE 'credit' END;
 v_control_total:=core10._finance_arap_net_v1(pay.id,l.account_id,
   CASE WHEN l.kind='ar' THEN 'credit' ELSE 'debit' END);
 SELECT coalesce(sum(line.amount),0) INTO v_asset_total
 FROM core10.finance_journal_lines_v1 line
 JOIN core10.finance_accounts_v1 a ON a.id=line.account_id
 WHERE line.journal_id=pay.id
   AND line.account_id<>l.account_id
   AND line.side=v_side
   AND a.category='asset'
   AND a.business_id=l.business_id AND a.tenant_id=l.tenant_id
   AND a.currency=pay.currency AND a.legal_entity_id=pay.legal_entity_id;
 IF v_control_total<=0 OR v_asset_total<v_control_total
 THEN RAISE EXCEPTION 'FIN_ARAP_SETTLEMENT_ASSET_COUNTERPART_MISSING'; END IF;
 RETURN NEW;
END $body$;

CREATE OR REPLACE FUNCTION core10.finance_arap_trace_v1(p_link bigint)
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
   'payment_provenance','manual_asset_counterpart_not_bank_attested',
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


DROP TRIGGER finance_sales_collection_no_truncate_v1 ON core10.finance_sales_collections_v1;
DROP TRIGGER finance_sales_collection_immutable_v1 ON core10.finance_sales_collections_v1;
DROP FUNCTION core10._finance_sales_collection_immutable_v1();
DROP TABLE core10.finance_sales_collections_v1;
DELETE FROM core10.control_catalog_v1 WHERE feature_key='finance.sales_collection'
 AND pack='NP06';
