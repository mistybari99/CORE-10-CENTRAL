-- Deterministic fake events for GOV-003 features 08/09 (synthetic, DEMO / NOT LIVE).
-- Run as superuser; every statement below switches to the trusted backend role + an inert fixture actor.
-- Actors: bizOwnerB1 = 1d..0002 (owner), staffS1 = 1d..0003 (staff at Site 1), t2Owner = 1d..0006.
\set ON_ERROR_STOP on
set role c10g3_backend;

-- Owner events, business B1 (Tenant T1) ------------------------------------------------------------
set request.jwt.claim.sub = '1d000000-0000-4000-8000-000000000002';
-- (a2) the same command + content under three DIFFERENT idempotency keys (duplicate submission)
select c10_gov003_demo.append_event('11111111-1111-4111-8111-111111111111','b1000000-0000-4000-8000-000000000001',null,null,
  'erp.pos','order-1001','v1','sale.recorded', timestamptz '2026-11-10T09:00:00Z','corr-dupc-1','dupc-key-0001',
  '{"amount_minor":"12500","currency":"bdt"}'::jsonb,null,'finance');
select c10_gov003_demo.append_event('11111111-1111-4111-8111-111111111111','b1000000-0000-4000-8000-000000000001',null,null,
  'erp.pos','order-1001','v1','sale.recorded', timestamptz '2026-11-10T09:00:20Z','corr-dupc-2','dupc-key-0002',
  '{"amount_minor":"12500","currency":"bdt"}'::jsonb,null,'finance');
select c10_gov003_demo.append_event('11111111-1111-4111-8111-111111111111','b1000000-0000-4000-8000-000000000001',null,null,
  'erp.pos','order-1001','v1','sale.recorded', timestamptz '2026-11-10T09:00:40Z','corr-dupc-3','dupc-key-0003',
  '{"amount_minor":"12500","currency":"bdt"}'::jsonb,null,'finance');
-- (b2) a supplier feed that then goes silent
select c10_gov003_demo.append_event('11111111-1111-4111-8111-111111111111','b1000000-0000-4000-8000-000000000001',null,null,
  'erp.supplier_feed','feed-001','v1','supplier.sync', timestamptz '2026-11-09T08:00:00Z','corr-feed-1','feed-key-0001',
  '{"status":"ok","count":"12"}'::jsonb,null,'operational');
select c10_gov003_demo.append_event('11111111-1111-4111-8111-111111111111','b1000000-0000-4000-8000-000000000001',null,null,
  'erp.supplier_feed','feed-002','v1','supplier.sync', timestamptz '2026-11-09T08:05:00Z','corr-feed-2','feed-key-0002',
  '{"status":"ok","count":"7"}'::jsonb,null,'operational');
-- an OWNER issuing a sensitive command is NOT an unauthorized-command signal (negative control)
select c10_gov003_demo.append_event('11111111-1111-4111-8111-111111111111','b1000000-0000-4000-8000-000000000001',null,null,
  'erp.approvals','appr-owner-1','v1','approval.grant', timestamptz '2026-11-10T11:05:00Z','corr-appr-o','appr-key-0001',
  '{"status":"approved"}'::jsonb,null,'access');

-- Staff events, business B1 / Site 1 -----------------------------------------------------------------
set request.jwt.claim.sub = '1d000000-0000-4000-8000-000000000003';
-- (b1) volume burst: 7 stock movements inside one 10-minute window
select c10_gov003_demo.append_event('11111111-1111-4111-8111-111111111111','b1000000-0000-4000-8000-000000000001',
  '51000000-0000-4000-8000-000000000001',null,
  'erp.stock','mv-00' || i,'v1','stock.moved', timestamptz '2026-11-10T10:00:10Z' + (i * interval '30 seconds'),
  'corr-vol-' || i,'vol-key-000' || i,
  jsonb_build_object('item_ref','item-1','quantity_milli', (1000 + i)::text),null,'inventory')
  from generate_series(1,7) as i;
-- (c1) a sensitive command from staff (no owner role): advisory signal expected
select c10_gov003_demo.append_event('11111111-1111-4111-8111-111111111111','b1000000-0000-4000-8000-000000000001',
  '51000000-0000-4000-8000-000000000001',null,
  'erp.approvals','appr-77','v1','approval.override', timestamptz '2026-11-10T11:00:00Z','corr-appr-1','appr-key-0077',
  '{"status":"approved","reason_code":"manager_absent"}'::jsonb,null,'access');
-- (a1) idempotency key: first use, two exact replays, then a changed payload (conflict) - all LOGGED
select c10_gov003_demo.append_event_logged('11111111-1111-4111-8111-111111111111','b1000000-0000-4000-8000-000000000001',
  '51000000-0000-4000-8000-000000000001',null,
  'erp.pos','order-2002','v1','sale.recorded', timestamptz '2026-11-10T09:30:00Z','corr-idem-1','idem-dup-0001',
  '{"amount_minor":"5000","currency":"bdt"}'::jsonb,null,'finance');
select c10_gov003_demo.append_event_logged('11111111-1111-4111-8111-111111111111','b1000000-0000-4000-8000-000000000001',
  '51000000-0000-4000-8000-000000000001',null,
  'erp.pos','order-2002','v1','sale.recorded', timestamptz '2026-11-10T09:30:00Z','corr-idem-1','idem-dup-0001',
  '{"amount_minor":"5000","currency":"bdt"}'::jsonb,null,'finance');
select c10_gov003_demo.append_event_logged('11111111-1111-4111-8111-111111111111','b1000000-0000-4000-8000-000000000001',
  '51000000-0000-4000-8000-000000000001',null,
  'erp.pos','order-2002','v1','sale.recorded', timestamptz '2026-11-10T09:30:00Z','corr-idem-1','idem-dup-0001',
  '{"amount_minor":"5000","currency":"bdt"}'::jsonb,null,'finance');
select c10_gov003_demo.append_event_logged('11111111-1111-4111-8111-111111111111','b1000000-0000-4000-8000-000000000001',
  '51000000-0000-4000-8000-000000000001',null,
  'erp.pos','order-2002','v1','sale.recorded', timestamptz '2026-11-10T09:30:00Z','corr-idem-1','idem-dup-0001',
  '{"amount_minor":"9999","currency":"bdt"}'::jsonb,null,'finance');

-- Tenant T2 / Business C: its own duplicate content (must never surface in T1 views) -------------------
set request.jwt.claim.sub = '1d000000-0000-4000-8000-000000000006';
select c10_gov003_demo.append_event('22222222-2222-4222-8222-222222222222','b1000000-0000-4000-8000-000000000003',null,null,
  'erp.pos','order-9001','v1','sale.recorded', timestamptz '2026-11-10T09:00:00Z','corr-t2-' || i,'t2dup-key-000' || i,
  '{"amount_minor":"777","currency":"bdt"}'::jsonb,null,'finance')
  from generate_series(1,3) as i;
reset role;
