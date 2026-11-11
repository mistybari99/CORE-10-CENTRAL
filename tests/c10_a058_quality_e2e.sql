\set ON_ERROR_STOP on
\echo CORE10 A058 QUALITY + LOT + RECALL: disposable PostgreSQL E2E
-- Three businesses / two tenants, owner+manager+site staff+revoked+investor+anon.
-- Base A018 fixture and serialized A018 inventory engine must already exist.

INSERT INTO c10_demo.items(id,tenant_id,business_id,sku) VALUES
 (8010,1,101,'DEMO-PERISHABLE-A'),
 (8011,1,101,'DEMO-FINISHED-GOOD-B'),
 (8012,1,102,'DEMO-SECOND-BUSINESS'),
 (9010,2,201,'DEMO-FOREIGN-TENANT');

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE a bigint; b bigint; c bigint; d bigint; q bigint; z bigint; t bigint; r bigint;
 v_pass jsonb:='[{"code":"appearance","ok":true},{"code":"food_temp","ok":true}]'::jsonb;
BEGIN
 -- Guarded enrollment of pristine SKU and idempotent registration.
 IF NOT c10_demo.quality_enable_item_v1(101,8010) OR NOT c10_demo.quality_enable_item_v1(101,8011)
 THEN RAISE EXCEPTION 'enrollment failed'; END IF;
 a:=c10_demo.quality_register_lot_v1(101,8010,1001,'LOT-A-001','purchase','DEMO-PO-0001',
  CURRENT_DATE-1,CURRENT_DATE+10,'a058-register-a');
 IF a<>c10_demo.quality_register_lot_v1(101,8010,1001,'LOT-A-001','purchase','DEMO-PO-0001',
  CURRENT_DATE-1,CURRENT_DATE+10,'a058-register-a') THEN RAISE EXCEPTION 'register replay'; END IF;
 BEGIN
  PERFORM c10_demo.quality_register_lot_v1(101,8010,1001,'LOT-A-002','purchase','DEMO-PO-0001',
   CURRENT_DATE-1,CURRENT_DATE+10,'a058-register-a');
  RAISE EXCEPTION 'register payload conflict wrongly accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'quality_idempotency_conflict' THEN RAISE; END IF;
 END;
 q:=c10_demo.quality_stock_v1(a,5001,25,'receipt','Demo receiving','a058-receive-a');
 IF q<>c10_demo.quality_stock_v1(a,5001,25,'receipt','Demo receiving','a058-receive-a')
 THEN RAISE EXCEPTION 'receipt replay duplicated'; END IF;
 IF (SELECT count(*) FROM c10_demo.stock_movements WHERE item_id=8010)<>1
 THEN RAISE EXCEPTION 'duplicate canonical stock receipt'; END IF;
 BEGIN
  PERFORM c10_demo.post_stock_event(5001,8010,1,'bypass-tracked-item');
  RAISE EXCEPTION 'generic stock bypass wrongly accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'tracked_item_requires_quality_command' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.quality_stock_v1(a,5001,1,'issue','Demo sale','a058-before-qc');
  RAISE EXCEPTION 'quarantine issue wrongly accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'quality_lot_not_sellable' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.quality_inspect_v1(a,'pass','[{"code":"temp","ok":false}]'::jsonb,'bad','a058-falsepass');
  RAISE EXCEPTION 'false passing inspection accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'quality_false_pass' THEN RAISE; END IF;
 END;
 PERFORM c10_demo.quality_inspect_v1(a,'pass',v_pass,'Both demo checks pass','a058-inspection-a');
 PERFORM c10_demo.quality_decide_lot_v1(a,'release','Manager reviewed','a058-release-a');
 q:=c10_demo.quality_stock_v1(a,5001,5,'issue','Demo shipment','a058-issue-a');
 IF q<>c10_demo.quality_stock_v1(a,5001,5,'issue','Demo shipment','a058-issue-a')
 THEN RAISE EXCEPTION 'issue replay'; END IF;
 IF (SELECT on_hand FROM c10_demo.quality_balances_v1 WHERE location_id=5001 AND lot_id=a)<>20
 THEN RAISE EXCEPTION 'lot receipt-issue math mismatch'; END IF;
 BEGIN
  PERFORM c10_demo.quality_stock_v1(a,5001,50,'issue','Demo overdraw','a058-overdraw');
  RAISE EXCEPTION 'overdraw wrongly accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'quality_insufficient_lot_stock' THEN RAISE; END IF;
 END;
 b:=c10_demo.quality_register_lot_v1(101,8010,1001,'LOT-B-002','purchase','DEMO-PO-0002',
  CURRENT_DATE-1,CURRENT_DATE+3,'a058-register-b');
 PERFORM c10_demo.quality_stock_v1(b,5001,4,'receipt','Second demo receipt','a058-receive-b');
 PERFORM c10_demo.quality_inspect_v1(b,'pass',v_pass,'Approved','a058-inspection-b');
 PERFORM c10_demo.quality_decide_lot_v1(b,'release','Approved','a058-release-b');
 SELECT lot_id,suggested INTO z,t FROM c10_demo.quality_fefo_v1(101,8010,1001,6) ORDER BY expiry_date LIMIT 1;
 IF z<>b OR t<>4 THEN RAISE EXCEPTION 'FEFO must pick earlier expiry first: % %',z,t; END IF;
 q:=c10_demo.quality_transfer_v1(a,5001,5002,8,'a058-transfer-a');
 IF q<>c10_demo.quality_transfer_v1(a,5001,5002,8,'a058-transfer-a')
 THEN RAISE EXCEPTION 'transfer replay'; END IF;
 IF (SELECT on_hand FROM c10_demo.quality_balances_v1 WHERE location_id=5001 AND lot_id=a)<>12 OR
  (SELECT on_hand FROM c10_demo.quality_balances_v1 WHERE location_id=5002 AND lot_id=a)<>8
 THEN RAISE EXCEPTION 'transfer lot balances'; END IF;
 IF EXISTS(SELECT 1 FROM c10_demo.quality_reconciliation_v1 WHERE NOT reconciled)
 THEN RAISE EXCEPTION 'canonical stock and lot reconciliation mismatch'; END IF;
 -- Parent ingredient -> finished good lineage, then recursive immediate recall.
 c:=c10_demo.quality_register_lot_v1(101,8011,1002,'CAKE-BATCH-C','production','DEMO-WO-0001',
 CURRENT_DATE,CURRENT_DATE+5,'a058-register-c');
 PERFORM c10_demo.quality_stock_v1(c,5002,3,'receipt','Finished batch','a058-receive-c');
 PERFORM c10_demo.quality_inspect_v1(c,'pass',v_pass,'Approved','a058-inspection-c');
 PERFORM c10_demo.quality_decide_lot_v1(c,'release','Approved','a058-release-c');
 PERFORM c10_demo.quality_link_genealogy_v1(a,c,'a058-link-a-c');
 BEGIN
  PERFORM c10_demo.quality_link_genealogy_v1(c,a,'a058-cycle');
  RAISE EXCEPTION 'genealogy cycle wrongly accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'quality_genealogy_cycle' THEN RAISE; END IF;
 END;
 r:=c10_demo.quality_start_recall_v1(a,'critical','Simulated allergen recall for regression','a058-recall-a');
 IF r<>c10_demo.quality_start_recall_v1(a,'critical','Simulated allergen recall for regression','a058-recall-a')
 THEN RAISE EXCEPTION 'recall replay'; END IF;
 IF (SELECT count(*) FROM c10_demo.quality_recall_impacts_v1 WHERE recall_id=r)<>2 OR
  (SELECT status FROM c10_demo.quality_lots_v1 WHERE id=c)<>'recalled'
 THEN RAISE EXCEPTION 'recursive recall failed'; END IF;
 IF (SELECT status FROM c10_demo.quality_lots_v1 WHERE id=b)<>'released'
 THEN RAISE EXCEPTION 'unrelated lot accidentally recalled'; END IF;
 BEGIN
  PERFORM c10_demo.quality_stock_v1(c,5002,1,'issue','Should fail','a058-recalled-sale');
  RAISE EXCEPTION 'sale of recalled stock wrongly accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'quality_lot_not_sellable' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.quality_close_recall_v1(r,'a058-close-too-early');
  RAISE EXCEPTION 'recall closed while stock remained';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'quality_recall_stock_remaining' THEN RAISE; END IF;
 END;
 PERFORM c10_demo.quality_stock_v1(a,5001,12,'disposal','Recall disposal','a058-dispose-a1');
 PERFORM c10_demo.quality_stock_v1(a,5002,8,'disposal','Recall disposal','a058-dispose-a2');
 PERFORM c10_demo.quality_stock_v1(c,5002,3,'disposal','Recall disposal','a058-dispose-c');
 PERFORM c10_demo.quality_close_recall_v1(r,'a058-close-clean');
 IF (SELECT status FROM c10_demo.quality_recalls_v1 WHERE id=r)<>'closed'
 THEN RAISE EXCEPTION 'recall closure missing'; END IF;
 IF EXISTS(SELECT 1 FROM c10_demo.quality_reconciliation_v1 WHERE NOT reconciled)
 THEN RAISE EXCEPTION 'reconciliation failed after recall disposal'; END IF;
 IF (SELECT sum(delta) FROM c10_demo.quality_movements_v1 WHERE command_id=
  (SELECT id FROM c10_demo.quality_commands_v1 WHERE request_key='a058-transfer-a'))<>0
 THEN RAISE EXCEPTION 'lot transfer must be zero sum'; END IF;
 IF (SELECT sum(delta) FROM c10_demo.stock_movements WHERE item_id=8010)<>4
 THEN RAISE EXCEPTION 'unrecalled lot stock conservation failed'; END IF;
END $$;
COMMIT;
-- Permit integrity is checked by the CI database owner: app identities cannot read permits.
DO $ BEGIN
 IF (SELECT count(*) FROM c10_demo.quality_stock_permits_v1 WHERE NOT consumed)<>0
 THEN RAISE EXCEPTION 'unused stock permit persisted'; END IF;
END $;

-- Another registered business cannot be enrolled with existing stock from untracked history.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
BEGIN
 PERFORM c10_demo.post_stock_event(5001,8001,1,'a058-pre-existing-normal-stock');
 BEGIN
  PERFORM c10_demo.quality_enable_item_v1(101,8001);
  RAISE EXCEPTION 'existing stock silently adopted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'quality_existing_stock_requires_backfill' THEN RAISE; END IF;
 END;
END $$;
ROLLBACK;

-- Business manager can inspect (but cannot decide/release) and cannot cross business boundaries.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
DO $$
DECLARE v_lot bigint; v_checks jsonb:='[{"code":"look","ok":true}]'::jsonb;
BEGIN
 v_lot:=(SELECT id FROM c10_demo.quality_lots_v1 WHERE lot_code='LOT-B-002');
 PERFORM c10_demo.quality_inspect_v1(v_lot,'pass',v_checks,'manager reinspection','a058-manager-check');
 BEGIN
  PERFORM c10_demo.quality_decide_lot_v1(v_lot,'hold','manager cannot override','a058-manager-hold');
  RAISE EXCEPTION 'manager overrode owner-held decision';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'quality_manager_decision_denied' THEN RAISE; END IF;
 END;
END $$;
COMMIT;

-- Site staff can see only his own site lot balances, not factory-only data, cannot recall/inspect.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
DO $$
DECLARE v_lot bigint;
BEGIN
 IF EXISTS(SELECT 1 FROM c10_demo.quality_balances_v1 WHERE location_id=5002)
 THEN RAISE EXCEPTION 'site-only quality balance leak'; END IF;
 v_lot:=(SELECT id FROM c10_demo.quality_lots_v1 WHERE lot_code='LOT-B-002');
 BEGIN
  PERFORM c10_demo.quality_start_recall_v1(v_lot,'internal','Unauthorized test','a058-staff-recall');
  RAISE EXCEPTION 'site staff started recall';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'quality_recall_owner_required' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.quality_transfer_v1(v_lot,5001,5002,1,'a058-staff-cross-site');
  RAISE EXCEPTION 'site staff transferred to ungranted site';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'quality_transfer_scope_denied' THEN RAISE; END IF;
 END;
END $$;
ROLLBACK;

-- Unrelated tenant, investor and revoked users must see nothing and must be denied writes.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM c10_demo.quality_lots_v1 WHERE business_id=101) OR
  EXISTS(SELECT 1 FROM c10_demo.quality_movements_v1 WHERE business_id=101)
 THEN RAISE EXCEPTION 'cross tenant quality leak'; END IF;
 BEGIN
  PERFORM c10_demo.quality_enable_item_v1(101,8010);
  RAISE EXCEPTION 'foreign owner enrolled tracked item';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'quality_owner_required' THEN RAISE; END IF;
 END;
END $$;
ROLLBACK;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','55555555-5555-4555-8555-555555555555',true);
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM c10_demo.quality_lots_v1 WHERE business_id=101)
 THEN RAISE EXCEPTION 'investor quality metadata leak'; END IF;
 BEGIN
  PERFORM c10_demo.quality_enable_item_v1(101,8010);
  RAISE EXCEPTION 'investor gained tracking control';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'quality_owner_required' THEN RAISE; END IF;
 END;
END $$;
ROLLBACK;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','66666666-6666-4666-8666-666666666666',true);
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM c10_demo.quality_lots_v1 WHERE business_id=101)
 THEN RAISE EXCEPTION 'revoked manager quality leak'; END IF;
END $$;
ROLLBACK;

BEGIN;
SET LOCAL ROLE anon;
DO $$
BEGIN
 BEGIN
  PERFORM count(*) FROM c10_demo.quality_lots_v1;
  RAISE EXCEPTION 'anonymous read accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM c10_demo.quality_enable_item_v1(101,8010);
  RAISE EXCEPTION 'anonymous mutate accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;

-- Even authenticated owner cannot bypass immutable audit / quality movement tables.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
BEGIN
 BEGIN
  UPDATE c10_demo.quality_movements_v1 SET delta=100 WHERE kind='receipt';
  RAISE EXCEPTION 'direct quality journal update accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  INSERT INTO c10_demo.quality_stock_permits_v1
  (tenant_id,business_id,location_id,item_id,request_key,delta,actor_id)
  VALUES(1,101,5001,8010,'forged',5,c10_demo.actor_uid());
  RAISE EXCEPTION 'public stock permit mint accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM c10_demo.quality_claim_v1(1,101,'evil','forged','{}'::jsonb);
  RAISE EXCEPTION 'internal claim helper publicly callable';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
\echo PASS: A058 QC, idempotent lots/stock, held/released gate, FEFO, two-site transfer, genealogy, recursive recall, disposal, ledger reconciliation and tenant/user isolation.
\echo LIMIT: disposable synthetic DB / not signed actual Supabase session, live SG backfill or production deployment.
