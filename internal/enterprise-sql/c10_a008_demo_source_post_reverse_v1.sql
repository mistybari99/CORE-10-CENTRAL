-- GOV-002 disposable synthetic stock command execution and compensating reversal.
-- For isolated PostgreSQL17 ONLY; NOT an SG migration / live inventory feature.
-- Applies AFTER A018 seed + A008 + typed + route + threshold extensions.
-- One approval request + original immutable payload and live source version must
-- match IN THE SAME TX as a source-bound ledger write. NEVER trust a UI checkbox.
-- Existing c10_demo.stock_movements is disposable; no production stock/finance.
-- This exercise intentionally supports positive-only, KG-only demo adjustments.

CREATE TABLE c10_demo.approval_demo_stock_commands_v1 (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, site_id bigint NOT NULL,
 location_id bigint NOT NULL, item_id bigint NOT NULL,
 delta numeric(15,3) NOT NULL CHECK(delta>0 AND delta<=1000),
 source_version bigint NOT NULL DEFAULT 1 CHECK(source_version>0),
 status text NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','posted','reversed')),
 request_key text NOT NULL CHECK(request_key ~ '^[A-Za-z0-9_-]{8,128}$'),
 created_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 approved_request_id bigint REFERENCES c10_demo.approval_requests(id),
 execution_key text, posted_movement_id bigint REFERENCES c10_demo.stock_movements(id),
 posted_at timestamptz,
 UNIQUE(business_id,request_key),
 UNIQUE(posted_movement_id),
 FOREIGN KEY(location_id,tenant_id,business_id,site_id)
  REFERENCES c10_demo.stock_locations(id,tenant_id,business_id,site_id),
 FOREIGN KEY(item_id,tenant_id,business_id)
  REFERENCES c10_demo.items(id,tenant_id,business_id),
 CHECK (
   (status='draft' AND approved_request_id IS NULL
    AND execution_key IS NULL AND posted_movement_id IS NULL AND posted_at IS NULL)
   OR (status IN ('posted','reversed') AND approved_request_id IS NOT NULL
    AND execution_key IS NOT NULL AND posted_movement_id IS NOT NULL AND posted_at IS NOT NULL)
 )
);
CREATE TABLE c10_demo.approval_demo_stock_revisions_v1 (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 command_id bigint NOT NULL REFERENCES c10_demo.approval_demo_stock_commands_v1(id),
 tenant_id bigint NOT NULL,business_id bigint NOT NULL,
 actor_id uuid NOT NULL, old_version bigint NOT NULL, new_version bigint NOT NULL,
 old_delta numeric(15,3) NOT NULL,new_delta numeric(15,3) NOT NULL,
 request_key text NOT NULL CHECK(request_key ~ '^[A-Za-z0-9_-]{8,128}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(command_id,request_key), UNIQUE(command_id,new_version),
 CHECK(new_version=old_version+1)
);
CREATE TABLE c10_demo.approval_demo_stock_reversals_v1 (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 command_id bigint NOT NULL UNIQUE REFERENCES c10_demo.approval_demo_stock_commands_v1(id),
 tenant_id bigint NOT NULL,business_id bigint NOT NULL,
 request_key text NOT NULL CHECK(request_key ~ '^[A-Za-z0-9_-]{8,128}$'),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 8 AND 160),
 created_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','applied')),
 approved_request_id bigint REFERENCES c10_demo.approval_requests(id),
 execution_key text,reverse_movement_id bigint REFERENCES c10_demo.stock_movements(id),
 applied_at timestamptz,
 UNIQUE(business_id,request_key), UNIQUE(reverse_movement_id),
 CHECK (
  (status='pending' AND approved_request_id IS NULL AND execution_key IS NULL
   AND reverse_movement_id IS NULL AND applied_at IS NULL)
  OR (status='applied' AND approved_request_id IS NOT NULL AND execution_key IS NOT NULL
   AND reverse_movement_id IS NOT NULL AND applied_at IS NOT NULL)
 )
);
CREATE TABLE c10_demo.approval_demo_execution_receipts_v1 (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,business_id bigint NOT NULL,
 command_id bigint NOT NULL REFERENCES c10_demo.approval_demo_stock_commands_v1(id),
 kind text NOT NULL CHECK(kind IN ('post','reverse')),
 approval_request_id bigint NOT NULL REFERENCES c10_demo.approval_requests(id),
 approval_event_id bigint NOT NULL REFERENCES c10_demo.approval_events(id),
 movement_id bigint NOT NULL UNIQUE REFERENCES c10_demo.stock_movements(id),
 actor_id uuid NOT NULL, original_movement_id bigint REFERENCES c10_demo.stock_movements(id),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(command_id,kind), UNIQUE(approval_request_id),
 CHECK((kind='post' AND original_movement_id IS NULL)
    OR(kind='reverse' AND original_movement_id IS NOT NULL))
);
ALTER TABLE c10_demo.approval_demo_stock_commands_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE c10_demo.approval_demo_stock_revisions_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE c10_demo.approval_demo_stock_reversals_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE c10_demo.approval_demo_execution_receipts_v1 ENABLE ROW LEVEL SECURITY;

CREATE POLICY demo_command_scoped_read_v1 ON c10_demo.approval_demo_stock_commands_v1
 FOR SELECT TO authenticated USING (
 c10_demo.can_manage(tenant_id,business_id)
 OR (created_by=c10_demo.actor_uid() AND c10_demo.can_business(tenant_id,business_id)));
CREATE POLICY demo_revision_scoped_read_v1 ON c10_demo.approval_demo_stock_revisions_v1
 FOR SELECT TO authenticated USING (
 c10_demo.can_manage(tenant_id,business_id)
 OR EXISTS(SELECT 1 FROM c10_demo.approval_demo_stock_commands_v1 c
            WHERE c.id=command_id AND c.created_by=c10_demo.actor_uid()
            AND c10_demo.can_business(c.tenant_id,c.business_id)));
CREATE POLICY demo_reversal_scoped_read_v1 ON c10_demo.approval_demo_stock_reversals_v1
 FOR SELECT TO authenticated USING (
 c10_demo.can_manage(tenant_id,business_id)
 OR (created_by=c10_demo.actor_uid() AND c10_demo.can_business(tenant_id,business_id)));
CREATE POLICY demo_receipt_scoped_read_v1 ON c10_demo.approval_demo_execution_receipts_v1
 FOR SELECT TO authenticated USING (
 c10_demo.can_manage(tenant_id,business_id)
 OR EXISTS(SELECT 1 FROM c10_demo.approval_demo_stock_commands_v1 c
    WHERE c.id=command_id AND c.created_by=c10_demo.actor_uid()
      AND c10_demo.can_business(c.tenant_id,c.business_id))
 );
REVOKE ALL ON c10_demo.approval_demo_stock_commands_v1,
 c10_demo.approval_demo_stock_revisions_v1,c10_demo.approval_demo_stock_reversals_v1,
 c10_demo.approval_demo_execution_receipts_v1 FROM PUBLIC,anon,authenticated;
GRANT SELECT ON c10_demo.approval_demo_stock_commands_v1,
 c10_demo.approval_demo_stock_revisions_v1,c10_demo.approval_demo_stock_reversals_v1,
 c10_demo.approval_demo_execution_receipts_v1 TO authenticated;

-- Server-derived, canonical payload includes every relevant source field.
CREATE FUNCTION c10_demo.demo_stock_payload_v1(
 p_command bigint
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE v c10_demo.approval_demo_stock_commands_v1%ROWTYPE;
BEGIN
 SELECT * INTO v FROM c10_demo.approval_demo_stock_commands_v1 WHERE id=p_command;
 IF NOT FOUND OR c10_demo.actor_uid() IS NULL
  OR NOT (c10_demo.can_manage(v.tenant_id,v.business_id)
          OR (v.created_by=c10_demo.actor_uid()
           AND c10_demo.can_business(v.tenant_id,v.business_id)))
 THEN RAISE EXCEPTION 'demo_source_not_authorized'; END IF;
 RETURN jsonb_build_object('amount',v.delta,'unit','KG',
  'command_id',v.id,'location_id',v.location_id,
  'item_id',v.item_id,'site_id',v.site_id,'version',v.source_version);
END $fn$;

CREATE FUNCTION c10_demo.prepare_demo_stock_v1(
 p_location bigint,p_item bigint,p_delta numeric,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE v_loc c10_demo.stock_locations%ROWTYPE;
        v_actor uuid:=c10_demo.actor_uid(); v_id bigint;
        v_old c10_demo.approval_demo_stock_commands_v1%ROWTYPE;
BEGIN
 IF v_actor IS NULL OR p_location IS NULL OR p_item IS NULL OR p_delta IS NULL
   OR p_delta<=0 OR p_delta>1000 OR p_delta<>trunc(p_delta,3)
   OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_demo_stock_source'; END IF;
 SELECT * INTO v_loc FROM c10_demo.stock_locations WHERE id=p_location;
 IF NOT FOUND OR NOT c10_demo.can_business(v_loc.tenant_id,v_loc.business_id)
  OR NOT c10_demo.can_site(v_loc.tenant_id,v_loc.business_id,v_loc.site_id,'stock.post')
  OR NOT EXISTS(SELECT 1 FROM c10_demo.items i WHERE i.id=p_item
    AND i.tenant_id=v_loc.tenant_id AND i.business_id=v_loc.business_id)
 THEN RAISE EXCEPTION 'demo_source_not_authorized'; END IF;
 INSERT INTO c10_demo.approval_demo_stock_commands_v1
 (tenant_id,business_id,site_id,location_id,item_id,delta,request_key,created_by)
 VALUES(v_loc.tenant_id,v_loc.business_id,v_loc.site_id,p_location,p_item,
        p_delta,p_key,v_actor)
 ON CONFLICT DO NOTHING RETURNING id INTO v_id;
 IF v_id IS NULL THEN
  SELECT * INTO v_old FROM c10_demo.approval_demo_stock_commands_v1
    WHERE business_id=v_loc.business_id AND request_key=p_key;
  IF NOT FOUND OR v_old.created_by<>v_actor OR v_old.location_id<>p_location
   OR v_old.item_id<>p_item OR v_old.delta<>p_delta
  THEN RAISE EXCEPTION 'demo_source_replay_conflict'; END IF;
  v_id:=v_old.id;
 END IF;
 RETURN v_id;
END $fn$;

CREATE FUNCTION c10_demo.revise_demo_stock_v1(
 p_command bigint,p_expected_version bigint,p_delta numeric,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE v c10_demo.approval_demo_stock_commands_v1%ROWTYPE;
        v_old c10_demo.approval_demo_stock_revisions_v1%ROWTYPE;
        v_actor uuid:=c10_demo.actor_uid();
BEGIN
 IF v_actor IS NULL OR p_command IS NULL OR p_expected_version IS NULL
  OR p_delta IS NULL OR p_delta<=0 OR p_delta>1000
  OR p_delta<>trunc(p_delta,3)
  OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_demo_source_edit'; END IF;
 SELECT * INTO v FROM c10_demo.approval_demo_stock_commands_v1
  WHERE id=p_command FOR UPDATE;
 IF NOT FOUND OR v.created_by<>v_actor OR
  NOT c10_demo.can_business(v.tenant_id,v.business_id)
 THEN RAISE EXCEPTION 'demo_source_not_authorized'; END IF;
 SELECT * INTO v_old FROM c10_demo.approval_demo_stock_revisions_v1
  WHERE command_id=p_command AND request_key=p_key;
 IF FOUND THEN
  IF v_old.actor_id<>v_actor OR v_old.old_version<>p_expected_version
   OR v_old.new_delta<>p_delta
  THEN RAISE EXCEPTION 'demo_revision_replay_conflict'; END IF;
  RETURN v_old.new_version;
 END IF;
 IF v.status<>'draft' OR v.source_version<>p_expected_version
 THEN RAISE EXCEPTION 'demo_source_stale_or_final'; END IF;
 UPDATE c10_demo.approval_demo_stock_commands_v1
  SET delta=p_delta,source_version=v.source_version+1 WHERE id=p_command;
 INSERT INTO c10_demo.approval_demo_stock_revisions_v1
  (command_id,tenant_id,business_id,actor_id,old_version,new_version,
   old_delta,new_delta,request_key)
 VALUES(p_command,v.tenant_id,v.business_id,v_actor,
   v.source_version,v.source_version+1,v.delta,p_delta,p_key);
 RETURN v.source_version+1;
END $fn$;

CREATE FUNCTION c10_demo.prepare_demo_reversal_v1(
 p_command bigint,p_reason text,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE v c10_demo.approval_demo_stock_commands_v1%ROWTYPE;
        v_old c10_demo.approval_demo_stock_reversals_v1%ROWTYPE;
        v_actor uuid:=c10_demo.actor_uid();v_id bigint;
BEGIN
 IF v_actor IS NULL OR p_command IS NULL OR p_reason IS NULL
  OR length(btrim(p_reason)) NOT BETWEEN 8 AND 160
  OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_demo_reversal'; END IF;
 SELECT * INTO v FROM c10_demo.approval_demo_stock_commands_v1
 WHERE id=p_command FOR UPDATE;
 IF NOT FOUND OR NOT c10_demo.can_business(v.tenant_id,v.business_id)
 THEN RAISE EXCEPTION 'demo_reversal_not_authorized'; END IF;
 IF v.status<>'posted' THEN RAISE EXCEPTION 'demo_reversal_invalid_source'; END IF;
 INSERT INTO c10_demo.approval_demo_stock_reversals_v1
  (command_id,tenant_id,business_id,request_key,reason,created_by)
 VALUES(p_command,v.tenant_id,v.business_id,p_key,btrim(p_reason),v_actor)
 ON CONFLICT DO NOTHING RETURNING id INTO v_id;
 IF v_id IS NULL THEN
  SELECT * INTO v_old FROM c10_demo.approval_demo_stock_reversals_v1
   WHERE command_id=p_command;
  IF NOT FOUND OR v_old.created_by<>v_actor
   OR v_old.request_key<>p_key OR v_old.reason<>btrim(p_reason)
  THEN RAISE EXCEPTION 'demo_reversal_replay_conflict'; END IF;
  v_id:=v_old.id;
 END IF;
 RETURN v_id;
END $fn$;

CREATE FUNCTION c10_demo.demo_reversal_payload_v1(
 p_reversal bigint
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE v c10_demo.approval_demo_stock_reversals_v1%ROWTYPE;
        v_c c10_demo.approval_demo_stock_commands_v1%ROWTYPE;
BEGIN
 SELECT * INTO v FROM c10_demo.approval_demo_stock_reversals_v1
 WHERE id=p_reversal;
 IF NOT FOUND OR c10_demo.actor_uid() IS NULL OR NOT
 (c10_demo.can_manage(v.tenant_id,v.business_id) OR
 (v.created_by=c10_demo.actor_uid() AND c10_demo.can_business(v.tenant_id,v.business_id)))
 THEN RAISE EXCEPTION 'demo_reversal_not_authorized'; END IF;
 SELECT * INTO v_c FROM c10_demo.approval_demo_stock_commands_v1
 WHERE id=v.command_id;
 RETURN jsonb_build_object('amount',v_c.delta,'unit','KG',
  'reversal_id',v.id,'command_id',v_c.id,
  'original_movement_id',v_c.posted_movement_id,'reason',v.reason);
END $fn$;

-- Cached JWT / caller identity is NOT adequate for an executor: assert the
-- original maker has a CURRENT active membership at moment of posting.
CREATE FUNCTION c10_demo.demo_maker_active_v1(
 p_tenant bigint,p_business bigint,p_user uuid
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=c10_demo,pg_catalog AS $fn$
 SELECT EXISTS(SELECT 1 FROM c10_demo.tenant_members t
  WHERE t.tenant_id=p_tenant AND t.user_id=p_user AND t.active
    AND t.role='tenant_owner')
 OR EXISTS(SELECT 1 FROM c10_demo.business_members m
  WHERE m.tenant_id=p_tenant AND m.business_id=p_business
    AND m.user_id=p_user AND m.active
    AND m.role IN ('manager','business_owner'));
$fn$;

CREATE FUNCTION c10_demo.execute_approved_demo_stock_v1(
 p_command bigint,p_approval bigint,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE v c10_demo.approval_demo_stock_commands_v1%ROWTYPE;
        v_req c10_demo.approval_requests%ROWTYPE;v_receipt bigint;v_move bigint;
        v_payload jsonb;
BEGIN
 IF p_command IS NULL OR p_approval IS NULL OR p_key IS NULL
  OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_demo_execution'; END IF;
 SELECT * INTO v FROM c10_demo.approval_demo_stock_commands_v1
  WHERE id=p_command FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'demo_source_missing'; END IF;
 IF v.status='posted' OR v.status='reversed' THEN
  IF v.approved_request_id=p_approval AND v.execution_key=p_key
  THEN RETURN v.posted_movement_id; END IF;
  RAISE EXCEPTION 'demo_execution_replay_conflict';
 END IF;
 IF v.status<>'draft' OR NOT c10_demo.demo_maker_active_v1(
  v.tenant_id,v.business_id,v.created_by)
 THEN RAISE EXCEPTION 'demo_maker_inactive_or_source_final'; END IF;
 SELECT * INTO v_req FROM c10_demo.approval_requests
  WHERE id=p_approval FOR UPDATE;
 IF NOT FOUND OR v_req.created_by<>v.created_by
   OR v_req.tenant_id<>v.tenant_id OR v_req.business_id<>v.business_id
 THEN RAISE EXCEPTION 'demo_approval_maker_or_scope_mismatch'; END IF;
 v_payload:=jsonb_build_object('amount',v.delta,'unit','KG',
  'command_id',v.id,'location_id',v.location_id,
  'item_id',v.item_id,'site_id',v.site_id,'version',v.source_version);
 v_receipt:=c10_demo.verify_approval_binding_v1(p_approval,v.business_id,
  'demo_stock','post_adjustment','demo-adjustment:'||v.id,
  v.source_version,v_payload);
 INSERT INTO c10_demo.stock_movements
  (tenant_id,business_id,site_id,location_id,item_id,delta,request_key,created_by)
 VALUES(v.tenant_id,v.business_id,v.site_id,v.location_id,v.item_id,v.delta,
  'gov002-post-'||v.id,v.created_by)
 RETURNING id INTO v_move;
 UPDATE c10_demo.approval_demo_stock_commands_v1
  SET status='posted',approved_request_id=p_approval,execution_key=p_key,
      posted_movement_id=v_move,posted_at=clock_timestamp()
 WHERE id=p_command;
 INSERT INTO c10_demo.approval_demo_execution_receipts_v1
  (tenant_id,business_id,command_id,kind,approval_request_id,
   approval_event_id,movement_id,actor_id)
 VALUES(v.tenant_id,v.business_id,v.id,'post',p_approval,v_receipt,
  v_move,v.created_by);
 RETURN v_move;
END $fn$;

CREATE FUNCTION c10_demo.execute_approved_demo_reversal_v1(
 p_reversal bigint,p_approval bigint,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE v_r c10_demo.approval_demo_stock_reversals_v1%ROWTYPE;
        v_c c10_demo.approval_demo_stock_commands_v1%ROWTYPE;
        v_req c10_demo.approval_requests%ROWTYPE;v_receipt bigint;v_move bigint;
        v_orig c10_demo.stock_movements%ROWTYPE;v_payload jsonb;
BEGIN
 IF p_reversal IS NULL OR p_approval IS NULL OR p_key IS NULL
  OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_demo_reversal_execution'; END IF;
 SELECT * INTO v_r FROM c10_demo.approval_demo_stock_reversals_v1
 WHERE id=p_reversal FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'demo_reversal_missing'; END IF;
 IF v_r.status='applied' THEN
  IF v_r.approved_request_id=p_approval AND v_r.execution_key=p_key
  THEN RETURN v_r.reverse_movement_id; END IF;
  RAISE EXCEPTION 'demo_reversal_execution_replay_conflict';
 END IF;
 SELECT * INTO v_c FROM c10_demo.approval_demo_stock_commands_v1
 WHERE id=v_r.command_id FOR UPDATE;
 IF NOT FOUND OR v_c.status<>'posted'
 THEN RAISE EXCEPTION 'demo_reversal_source_not_posted'; END IF;
 IF NOT c10_demo.demo_maker_active_v1(
  v_r.tenant_id,v_r.business_id,v_r.created_by)
 THEN RAISE EXCEPTION 'demo_reversal_maker_inactive'; END IF;
 SELECT * INTO v_orig FROM c10_demo.stock_movements
 WHERE id=v_c.posted_movement_id FOR SHARE;
 IF NOT FOUND OR v_orig.tenant_id<>v_c.tenant_id
   OR v_orig.business_id<>v_c.business_id OR v_orig.location_id<>v_c.location_id
   OR v_orig.item_id<>v_c.item_id OR v_orig.delta<>v_c.delta
 THEN RAISE EXCEPTION 'demo_original_ledger_mismatch'; END IF;
 SELECT * INTO v_req FROM c10_demo.approval_requests WHERE id=p_approval FOR UPDATE;
 IF NOT FOUND OR v_req.created_by<>v_r.created_by
  OR v_req.tenant_id<>v_r.tenant_id OR v_req.business_id<>v_r.business_id
 THEN RAISE EXCEPTION 'demo_reversal_approval_scope_mismatch'; END IF;
 v_payload:=jsonb_build_object('amount',v_c.delta,'unit','KG',
   'reversal_id',v_r.id,'command_id',v_c.id,
   'original_movement_id',v_c.posted_movement_id,'reason',v_r.reason);
 v_receipt:=c10_demo.verify_approval_binding_v1(p_approval,v_r.business_id,
  'demo_stock','reverse_adjustment','demo-reversal:'||v_r.id,1,v_payload);
 INSERT INTO c10_demo.stock_movements
  (tenant_id,business_id,site_id,location_id,item_id,delta,request_key,created_by)
 VALUES(v_c.tenant_id,v_c.business_id,v_c.site_id,v_c.location_id,v_c.item_id,
  -v_c.delta,'gov002-rev-'||v_r.id,v_r.created_by)
 RETURNING id INTO v_move;
 UPDATE c10_demo.approval_demo_stock_commands_v1
   SET status='reversed' WHERE id=v_c.id;
 UPDATE c10_demo.approval_demo_stock_reversals_v1
   SET status='applied',approved_request_id=p_approval,execution_key=p_key,
       reverse_movement_id=v_move,applied_at=clock_timestamp()
 WHERE id=p_reversal;
 INSERT INTO c10_demo.approval_demo_execution_receipts_v1
   (tenant_id,business_id,command_id,kind,approval_request_id,
    approval_event_id,movement_id,actor_id,original_movement_id)
 VALUES(v_c.tenant_id,v_c.business_id,v_c.id,'reverse',p_approval,v_receipt,
   v_move,v_r.created_by,v_c.posted_movement_id);
 RETURN v_move;
END $fn$;

-- Authenticated can prepare/edit/read but never directly apply ledger changes.
-- Only trusted service_role can invoke atomic execution adapters.
REVOKE ALL ON FUNCTION c10_demo.demo_stock_payload_v1(bigint)
 FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION c10_demo.demo_reversal_payload_v1(bigint)
 FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION c10_demo.prepare_demo_stock_v1(bigint,bigint,numeric,text)
 FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION c10_demo.revise_demo_stock_v1(bigint,bigint,numeric,text)
 FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION c10_demo.prepare_demo_reversal_v1(bigint,text,text)
 FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION c10_demo.demo_maker_active_v1(bigint,bigint,uuid)
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION c10_demo.execute_approved_demo_stock_v1(bigint,bigint,text)
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION c10_demo.execute_approved_demo_reversal_v1(bigint,bigint,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION c10_demo.demo_stock_payload_v1(bigint),
 c10_demo.demo_reversal_payload_v1(bigint),
 c10_demo.prepare_demo_stock_v1(bigint,bigint,numeric,text),
 c10_demo.revise_demo_stock_v1(bigint,bigint,numeric,text),
 c10_demo.prepare_demo_reversal_v1(bigint,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION c10_demo.execute_approved_demo_stock_v1(bigint,bigint,text),
 c10_demo.execute_approved_demo_reversal_v1(bigint,bigint,text)
 TO service_role;
-- IMPORTANT: this is a disposable demo ledger, NOT production stock.
