\set ON_ERROR_STOP on
\echo CORE10 A021/A022/A023: owner controls, contract ledger, scoped reports real PostgreSQL E2E
-- Synthetic seed fixtures loaded first; all writes are isolated to disposable DB.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
DO $$
DECLARE r bigint;
BEGIN
 r:=c10_demo.request_module_visibility_v1(
   101,'pos','hidden','Manager requested owner review','owner-hide-1');
 IF r<>c10_demo.request_module_visibility_v1(
   101,'pos','hidden','Manager requested owner review','owner-hide-1') THEN
  RAISE EXCEPTION 'idempotent module request changed identity';
 END IF;
 BEGIN
  PERFORM c10_demo.request_module_visibility_v1(
   101,'pos','locked','Mutated control request','owner-hide-1');
  RAISE EXCEPTION 'conflicting module request accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'owner_request_idempotency_conflict' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.decide_module_visibility_v1(r,'approve');
  RAISE EXCEPTION 'manager approved owner decision';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'owner_decision_denied' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.request_module_visibility_v1(
   102,'pos','hidden','Cross business request','manager-cross-business');
  RAISE EXCEPTION 'manager changed foreign business module';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'owner_control_request_denied' THEN RAISE; END IF;
 END;
 IF (SELECT visibility FROM c10_demo.business_module_settings_v1
  WHERE business_id=101 AND module_code='pos')<>'locked' THEN
  RAISE EXCEPTION 'request mutated module without owner review';
 END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE r bigint; n bigint; a bigint; q bigint; h bigint; over bigint;
    j integer; monthid bigint; eq1 bigint; eq2 bigint; eh bigint; x bigint;
BEGIN
 SELECT id INTO r FROM c10_demo.owner_module_requests_v1
 WHERE business_id=101 AND request_key='owner-hide-1';
 IF c10_demo.decide_module_visibility_v1(r,'approve')<>'approved' OR
    c10_demo.decide_module_visibility_v1(r,'approve')<>'approved' THEN
   RAISE EXCEPTION 'owner approval not idempotent';
 END IF;
 IF (SELECT visibility FROM c10_demo.business_module_settings_v1
  WHERE business_id=101 AND module_code='pos')<>'hidden' THEN
  RAISE EXCEPTION 'owner approval not applied';
 END IF;
 n:=c10_demo.request_module_visibility_v1(
  101,'pos','show','Please enable an untested module','owner-show-unready');
 BEGIN
  PERFORM c10_demo.decide_module_visibility_v1(n,'approve');
  RAISE EXCEPTION 'uncertified module activated';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'module_not_certified_or_not_enabled' THEN RAISE; END IF;
 END;
 IF (SELECT status FROM c10_demo.owner_module_requests_v1 WHERE id=n)<>'pending' OR
    (SELECT operational_enabled FROM c10_demo.business_module_settings_v1
      WHERE business_id=101 AND module_code='pos') THEN
   RAISE EXCEPTION 'failed certification rolled forward partially';
 END IF;
 IF c10_demo.decide_module_visibility_v1(n,'reject')<>'rejected' THEN
  RAISE EXCEPTION 'owner rejection failed'; END IF;
 IF (SELECT count(*) FROM c10_demo.owner_business_control_board_v1)<>2 OR
   EXISTS(SELECT 1 FROM c10_demo.owner_business_control_board_v1
     WHERE pending_owner_decisions<>0 OR production_certified) THEN
  RAISE EXCEPTION 'master owner board scope/false certification';
 END IF;
 -- Six months of OWNER-APPROVED, manually supplied business profit. 
 -- Jan +300, Feb -100, Mar +300, Apr/May/Jun +200 => Jan-Mar +500, Jan-Jun +1100.
 FOR j IN 1..6 LOOP
   monthid:=c10_demo.record_finance_month_v1(101,make_date(2026,j,1),
     1000,CASE WHEN j=2 THEN 1100 WHEN j>=4 THEN 800 ELSE 700 END,
     'manual-month-'||j);
   IF monthid<>c10_demo.record_finance_month_v1(101,make_date(2026,j,1),
     1000,CASE WHEN j=2 THEN 1100 WHEN j>=4 THEN 800 ELSE 700 END,
     'manual-month-'||j) THEN RAISE EXCEPTION 'profit month retry failed'; END IF;
   IF c10_demo.approve_finance_month_v1(monthid)<>'owner_approved'
   THEN RAISE EXCEPTION 'profit approval failed'; END IF;
 END LOOP;
 IF (SELECT count(*) FROM c10_demo.finance_months_v1 WHERE business_id=101
  AND status='owner_approved')<>6 OR
   (SELECT sum(net_profit) FROM c10_demo.finance_months_v1 WHERE business_id=101)<>1100
 THEN RAISE EXCEPTION '6 profit months and loss netting'; END IF;
 BEGIN
  PERFORM c10_demo.record_finance_month_v1(101,date '2026-01-01',
    1200,700,'manual-month-1');
  RAISE EXCEPTION 'profit months overwritten by conflicting request';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'finance_month_idempotency_conflict' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.record_finance_month_v1(201,date '2026-01-01',
    1000,100,'other-tenant');
  RAISE EXCEPTION 'owner created revenue in foreign customer tenant';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'finance_not_authorized' THEN RAISE; END IF;
 END;

 q:=c10_demo.create_funding_agreement_v1(
   101,'55555555-5555-4555-8555-555555555555','Q14-PROFIT',2000000,
   1400,3,date '2026-01-01',date '2026-07-01','agreement-q14');
 h:=c10_demo.create_funding_agreement_v1(
   101,'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','H16-PROFIT',2000000,
   1600,6,date '2026-01-01',date '2026-07-01','agreement-h16');
 IF q<>c10_demo.create_funding_agreement_v1(
   101,'55555555-5555-4555-8555-555555555555','Q14-PROFIT',2000000,
   1400,3,date '2026-01-01',date '2026-07-01','agreement-q14')
 THEN RAISE EXCEPTION 'funding agreement retry changed ID'; END IF;
 IF c10_demo.activate_funding_agreement_v1(q)<>'active' OR
    c10_demo.activate_funding_agreement_v1(h)<>'active'
 THEN RAISE EXCEPTION 'separate financing contracts not activated'; END IF;
 over:=c10_demo.create_funding_agreement_v1(
   101,'cccccccc-cccc-4ccc-8ccc-cccccccccccc','EXCESS-PROFIT',10000,
   8000,1,date '2026-01-01',date '2026-07-01','agreement-over-share');
 BEGIN
  PERFORM c10_demo.activate_funding_agreement_v1(over);
  RAISE EXCEPTION 'investor profit shares exceeded 100 percent';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'profit_shares_exceed_100_percent' THEN RAISE; END IF;
 END;
 IF (SELECT status FROM c10_demo.funding_agreements_v1 WHERE id=over)<>'draft' THEN
  RAISE EXCEPTION 'over-share agreement accidentally activated'; END IF;
 BEGIN
  PERFORM c10_demo.create_funding_agreement_v1(
   102,'55555555-5555-4555-8555-555555555555','FOREIGN-INVESTOR',2000,
   1000,3,date '2026-01-01',date '2026-07-01','foreign-investor');
  RAISE EXCEPTION 'investor incorrectly linked to another business';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'investor_not_assigned_to_business' THEN RAISE; END IF;
 END;
 eq1:=c10_demo.create_funding_entitlement_v1(q,date '2026-01-01','q-jan');
 eq2:=c10_demo.create_funding_entitlement_v1(q,date '2026-04-01','q-apr');
 eh:=c10_demo.create_funding_entitlement_v1(h,date '2026-01-01','h-jan');
 IF (SELECT amount FROM c10_demo.funding_entitlements_v1 WHERE id=eq1)<>70 OR
    (SELECT amount FROM c10_demo.funding_entitlements_v1 WHERE id=eq2)<>84 OR
    (SELECT amount FROM c10_demo.funding_entitlements_v1 WHERE id=eh)<>176 THEN
  RAISE EXCEPTION 'quarterly/semiannual entitlements incorrect';
 END IF;
 BEGIN
  PERFORM c10_demo.create_funding_entitlement_v1(h,date '2026-04-01','h-not-due');
  RAISE EXCEPTION 'semiannual entitlement allowed in wrong month';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'entitlement_outside_agreement_schedule' THEN RAISE; END IF;
 END;
 IF eq1<>c10_demo.create_funding_entitlement_v1(q,date '2026-01-01','q-jan')
 THEN RAISE EXCEPTION 'funding entitlement retry not idempotent'; END IF;
 x:=c10_demo.record_funding_payment_v1(eq1,40,'Bank receipt 001','pay-q-jan');
 IF x<>c10_demo.record_funding_payment_v1(eq1,40,'Bank receipt 001','pay-q-jan')
 THEN RAISE EXCEPTION 'payment idempotency failed'; END IF;
 PERFORM c10_demo.record_funding_payment_v1(eq2,20,'Cash voucher 002','pay-q-apr');
 PERFORM c10_demo.record_funding_payment_v1(eh,50,'Bank receipt 003','pay-h-jan');
 BEGIN
  PERFORM c10_demo.record_funding_payment_v1(eq1,40,'Excess 999','pay-over');
  RAISE EXCEPTION 'overpaid entitlement allowed';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'payment_exceeds_entitlement' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.record_funding_payment_v1(eq1,45,'Bank receipt 001','pay-q-jan');
  RAISE EXCEPTION 'payment replay with altered amount accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'funding_payment_idempotency_conflict' THEN RAISE; END IF;
 END;
 IF (SELECT sum(amount) FROM c10_demo.funding_entitlements_v1
      WHERE business_id=101)<>330 OR
    (SELECT sum(paid_amount) FROM c10_demo.funding_payments_v1 WHERE business_id=101)<>110 OR
    (SELECT sum(unpaid_balance) FROM c10_demo.investor_statement_v1
      WHERE business_id=101 AND entitlement_id IS NOT NULL)<>220 THEN
  RAISE EXCEPTION 'finance obligations, partial payouts or statement mismatch'; END IF;
 IF (SELECT count(*) FROM c10_demo.funding_agreements_v1
  WHERE business_id=101 AND status='active')<>2 THEN
  RAISE EXCEPTION 'draft overshare included as active contract';
 END IF;
END $$;
COMMIT;

-- Direct table modification must not bypass guarded RPCs.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
BEGIN
 BEGIN
  UPDATE c10_demo.business_module_settings_v1 SET operational_enabled=true
   WHERE business_id=101;
  RAISE EXCEPTION 'direct module activation allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  INSERT INTO c10_demo.funding_payments_v1(
   tenant_id,business_id,entitlement_id,paid_amount,evidence_reference,request_key,recorded_by)
  VALUES(1,101,1,100000,'Forged payment','bypass',c10_demo.actor_uid());
  RAISE EXCEPTION 'direct investor payment allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;

-- Confirm stock stays balanced across internal transfer and per-business reporting.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
SELECT c10_demo.post_stock_event(5001,8001,20,'report-receive');
SELECT c10_demo.transfer_stock_v1(5001,5002,8001,8,'report-xfer');
SELECT c10_demo.post_stock_event(5002,8001,-2,'report-external-issue');
SELECT c10_demo.post_stock_event(5003,8002,5,'other-business-receive');
DO $$
BEGIN
 IF (SELECT total_units_on_hand FROM c10_demo.business_inventory_report_v1
     WHERE business_id=101)<>18 OR
    (SELECT internal_transfers FROM c10_demo.business_inventory_report_v1
     WHERE business_id=101)<>1 OR
    (SELECT internal_transferred_units FROM c10_demo.business_inventory_report_v1
     WHERE business_id=101)<>8 OR
    (SELECT received_units_excluding_transfers FROM c10_demo.business_inventory_report_v1
     WHERE business_id=101)<>20 OR
    (SELECT issued_units_excluding_transfers FROM c10_demo.business_inventory_report_v1
     WHERE business_id=101)<>2 THEN
  RAISE EXCEPTION 'internal transfer doubled external receipts/issues'; END IF;
 IF (SELECT net_manual_profit FROM c10_demo.business_finance_report_v1
     WHERE business_id=101)<>1100 OR
    (SELECT recorded_investor_payments FROM c10_demo.business_finance_report_v1
     WHERE business_id=101)<>110 THEN
  RAISE EXCEPTION 'business finance report source ledger mismatch'; END IF;
 IF (SELECT visible_businesses FROM c10_demo.tenant_consolidated_kpi_v1
     WHERE tenant_id=1)<>2 OR
    (SELECT on_hand_units_all_skus FROM c10_demo.tenant_consolidated_kpi_v1
     WHERE tenant_id=1)<>23 OR
    (SELECT unpaid_investor_balance FROM c10_demo.tenant_consolidated_kpi_v1
     WHERE tenant_id=1)<>220 THEN
  RAISE EXCEPTION 'tenant rollup mismatched isolated businesses'; END IF;
 IF EXISTS(SELECT 1 FROM c10_demo.tenant_consolidated_kpi_v1
     WHERE enterprise_ready) THEN RAISE EXCEPTION 'false enterprise-ready'; END IF;
 IF EXISTS(SELECT 1 FROM c10_demo.owner_business_kpi_v1 WHERE
   operationally_certified OR unreconciled_location_items>0) THEN
  RAISE EXCEPTION 'bad readiness or ledger reconciliation';
 END IF;
END $$;
COMMIT;

-- Independent customer's stock never enters portfolio reports.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
SELECT c10_demo.post_stock_event(6001,9001,9,'customer-foreign-receive');
DO $$
BEGIN
 IF (SELECT count(*) FROM c10_demo.owner_business_kpi_v1)<>1 OR
   (SELECT count(*) FROM c10_demo.owner_business_kpi_v1
     WHERE tenant_id=1)<>0 OR
   (SELECT visible_businesses FROM c10_demo.tenant_consolidated_kpi_v1
     WHERE tenant_id=2)<>1 OR
   (SELECT on_hand_units_all_skus FROM c10_demo.tenant_consolidated_kpi_v1
     WHERE tenant_id=2)<>9 THEN
  RAISE EXCEPTION 'independent tenant rollup exposed owner records'; END IF;
 IF EXISTS(SELECT 1 FROM c10_demo.funding_agreements_v1 WHERE tenant_id=1) OR
    EXISTS(SELECT 1 FROM c10_demo.funding_payments_v1 WHERE tenant_id=1) THEN
  RAISE EXCEPTION 'cross-tenant finance privacy leak'; END IF;
END $$;
COMMIT;

-- Business owner sees own business finance, never sibling or tenant master.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
DO $$
BEGIN
 IF (SELECT count(*) FROM c10_demo.owner_business_control_board_v1)<>1 OR
    (SELECT count(*) FROM c10_demo.owner_business_kpi_v1)<>1 OR
    (SELECT count(*) FROM c10_demo.owner_business_kpi_v1 WHERE business_id=102)<>0 OR
    (SELECT count(*) FROM c10_demo.tenant_consolidated_kpi_v1)<>0 THEN
  RAISE EXCEPTION 'business owner elevated to master tenant reporting'; END IF;
 IF (SELECT count(*) FROM c10_demo.funding_agreements_v1 WHERE business_id=101)<>3 THEN
  RAISE EXCEPTION 'business owner missing own contracts'; END IF;
END $$;
COMMIT;

-- Manager can request module visibility, never see owner-only finance/boards.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM c10_demo.owner_business_kpi_v1) OR
    EXISTS(SELECT 1 FROM c10_demo.owner_business_control_board_v1) OR
    EXISTS(SELECT 1 FROM c10_demo.finance_months_v1) OR
    EXISTS(SELECT 1 FROM c10_demo.funding_entitlements_v1) THEN
  RAISE EXCEPTION 'manager escalated owner finance/read permission'; END IF;
 BEGIN
  PERFORM c10_demo.record_finance_month_v1(101,date '2026-08-01',1000,800,'manager-money');
  RAISE EXCEPTION 'manager wrote finance month';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'finance_not_authorized' THEN RAISE; END IF;
 END;
END $$;
COMMIT;

-- Investor sees only assigned agreement, entitlement and own payments, NOT raw profit or peers.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','55555555-5555-4555-8555-555555555555',true);
DO $$
BEGIN
 IF (SELECT count(*) FROM c10_demo.funding_agreements_v1)<>1 OR
    (SELECT count(*) FROM c10_demo.funding_entitlements_v1)<>2 OR
    (SELECT count(*) FROM c10_demo.funding_payments_v1)<>2 OR
    (SELECT count(*) FROM c10_demo.investor_statement_v1 WHERE entitlement_id IS NOT NULL)<>2 OR
    EXISTS(SELECT 1 FROM c10_demo.finance_months_v1) OR
    EXISTS(SELECT 1 FROM c10_demo.owner_business_kpi_v1) OR
    EXISTS(SELECT 1 FROM c10_demo.owner_module_requests_v1) THEN
  RAISE EXCEPTION 'investor privacy and owner separation failed'; END IF;
 BEGIN
  PERFORM c10_demo.create_funding_entitlement_v1(
   (SELECT id FROM c10_demo.funding_agreements_v1 LIMIT 1),
   date '2026-01-01','investor-sneak');
  RAISE EXCEPTION 'investor authorized its own payout';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'entitlement_not_authorized' THEN RAISE; END IF;
 END;
END $$;
COMMIT;
-- Revoked user and platform operator have zero tenant portfolio finance visibility.
DO $block$
DECLARE identity uuid;
BEGIN
 FOR identity IN SELECT unnest(ARRAY[
   '66666666-6666-4666-8666-666666666666'::uuid,
   '99999999-9999-4999-8999-999999999999'::uuid]) LOOP
  PERFORM set_config('request.jwt.claim.sub',identity::text,false);
  EXECUTE 'SET ROLE authenticated';
  IF EXISTS(SELECT 1 FROM c10_demo.owner_business_kpi_v1) OR
     EXISTS(SELECT 1 FROM c10_demo.investor_statement_v1) OR
     EXISTS(SELECT 1 FROM c10_demo.owner_module_requests_v1) THEN
   RAISE EXCEPTION 'revoked/operator finance leak'; END IF;
  EXECUTE 'RESET ROLE';
 END LOOP;
END $block$;
BEGIN;
SET LOCAL ROLE anon;
DO $$
BEGIN
 BEGIN
  PERFORM 1 FROM c10_demo.investor_statement_v1;
  RAISE EXCEPTION 'anonymous investor statement visible';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM c10_demo.decide_module_visibility_v1(1,'approve');
  RAISE EXCEPTION 'anonymous owner decision executable';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
\echo PASS: owner module approvals, non-activation, 2 investors across payout frequencies, overshare prevention, partial payout anti-overdraw, real scoped rollups, transfer zero-sales, staff/investor/revoked/anon isolation.
\echo LIMIT: manual-only financial inputs; production POS, audited actual cash transfer, COGS and live Supabase Auth are not connected.
