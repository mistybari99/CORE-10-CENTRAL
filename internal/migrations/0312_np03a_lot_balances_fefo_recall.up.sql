-- NP03A / B-012 (0209): lot dimension on the one stock ledger, lot balances, FEFO suggestion, lot hold / release,
-- lot-aware stock commands, recall with genealogy (Claude Agent K, block 0200-0299).
-- Reuse first: PR #73 (c10_a058_quality_lot_recall_v1.sql: genealogy, recursive recall, FEFO window, recalled lineage
-- lock), the 0203 lot master core10.inventory_lots_v1, the 0200 engine (post_stock_event / transfer_stock_v1), the 0201
-- command lifecycle (create / confirm / post through advance_inventory_command_v1, unchanged), the 0202 GOV-002 payload,
-- Owner Control (control_check_v1 + DEC-08 registry), canonical audit (source 'inventory').
-- ONE stock book (CHG-035): core10.stock_movements stays the only quantity ledger and stock_balances_v1 its serialized
-- location balance. NO quality_balances_v1 / second quantity table. The lot is a DIMENSION of a movement:
-- core10.stock_movement_lots_v1 breaks one ledger movement down by lot (movement_id -> lot, signed quantity, |sum| <=
-- |delta|; the rest of the movement is untracked). Lot balances are a derived read (view stock_lot_balances_v1 = sum
-- of that breakdown). The breakdown is written ONLY by the 0200 engine path inside the same transaction and under the
-- same location/item balance row lock that serializes the movement:
--  * a movement whose request key names a lot-bearing source document is tagged with that lot (resolver
--    _stock_movement_lot_v1: 'c10-grn-<grn>-<line>' -> GRN line lot, 'c10-ret-<return>-<line>' -> return line lot,
--    'c10-inv-cmd-<command>' -> command lot). These keys are server-built; both engine functions are internal (no API
--    EXECUTE). So 0203 GRN posting, 0207 supplier return and 0201 command posting need no CREATE OR REPLACE.
--  * a lot-less negative movement takes untracked stock first, then released lots FEFO (expiry, then lot id); a
--    transfer's in-leg mirrors the out-leg's lots, so a lot follows its stock between sites (recall finds it).
--  * invariant per location/item: every lot sub-balance >= 0 and sum(lot sub-balances) <= on_hand.
-- Lot-less behaviour is unchanged unless a lot is held / rejected / recalled: then lot-less issue may not consume that
-- lot's stock (lot_blocked_stock). Named-lot issue / transfer of a held, rejected, recalled or expired lot is refused;
-- adjust_out (write-off) and supplier return of a blocked lot are allowed (that is how blocked stock leaves).
-- Owner Control: inventory.lot_control (lot commands, hold / release; reason_required, separate_releaser) and
-- inventory.lot_recall (recall start / close, genealogy link; close_requires_zero_stock, include_genealogy).
-- Existing movements are backfilled in id order with the same rules (fail closed on any conflict).
DO $dep$ BEGIN
 IF to_regclass('core10.inventory_lots_v1') IS NULL OR to_regclass('core10.supplier_return_lines_v1') IS NULL
 OR to_regclass('core10.inventory_commands_v1') IS NULL
 OR to_regprocedure('core10.post_stock_event(bigint,bigint,numeric,text)') IS NULL
 OR to_regprocedure('core10.transfer_stock_v1(bigint,bigint,bigint,numeric,text)') IS NULL
 OR to_regprocedure('core10.create_inventory_command_v1(bigint,text,bigint,bigint,bigint,numeric,text,text)') IS NULL
 OR to_regprocedure('core10._inventory_approval_payload_v1(core10.inventory_commands_v1)') IS NULL
 THEN RAISE EXCEPTION 'INV_0209_DEPENDENCY_NOT_CONNECTED'; END IF;
END $dep$;

INSERT INTO core10.control_catalog_v1
 (feature_key,title_en,title_bn,pack,default_enabled,default_stages,max_stages,allow_site_scope,approval_domain,approval_action,params) VALUES
 ('inventory.lot_control','Pick, hold and release stock by lot','লট অনুযায়ী স্টক বাছাই, আটক ও মুক্ত করা','NP03A',true,0,0,true,NULL,NULL,
  '{"reason_required":{"type":"bool","default":true,"label_en":"Reason required to hold or release","label_bn":"আটক বা মুক্ত করতে কারণ বাধ্যতামূলক"},
    "separate_releaser":{"type":"bool","default":false,"label_en":"Releaser must differ from who held the lot","label_bn":"মুক্তকারী ও আটককারী আলাদা হবেন"}}'),
 ('inventory.lot_recall','Recall a lot and trace where its stock is','লট প্রত্যাহার ও স্টক কোথায় আছে তা খোঁজা','NP03A',true,0,0,false,NULL,NULL,
  '{"close_requires_zero_stock":{"type":"bool","default":true,"label_en":"Close only when no recalled stock is left","label_bn":"প্রত্যাহৃত স্টক শূন্য হলে তবেই বন্ধ"},
    "include_genealogy":{"type":"bool","default":true,"label_en":"Recall also lots made from the recalled lot","label_bn":"প্রত্যাহৃত লট থেকে তৈরি লটও প্রত্যাহার"}}');

-- ---------- lot master additions: who held a lot, when, why ----------
ALTER TABLE core10.inventory_lots_v1
 ADD COLUMN held_by uuid, ADD COLUMN held_at timestamptz,
 ADD COLUMN hold_reason text CHECK (hold_reason IS NULL OR length(btrim(hold_reason)) BETWEEN 3 AND 300);
ALTER TABLE core10.inventory_lots_v1 ADD CONSTRAINT inventory_lots_v1_hold_v1
 CHECK ((status='held') = (held_by IS NOT NULL) AND (held_by IS NULL) = (held_at IS NULL)
    AND (hold_reason IS NULL OR held_by IS NOT NULL));

-- ---------- the lot dimension of the one ledger ----------
CREATE TABLE core10.stock_movement_lots_v1 (
 movement_id bigint NOT NULL REFERENCES core10.stock_movements(id),
 lot_id bigint NOT NULL,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, site_id bigint NOT NULL,
 location_id bigint NOT NULL, item_id bigint NOT NULL,
 quantity numeric(15,3) NOT NULL CHECK (quantity<>0 AND quantity=round(quantity,3)),
 PRIMARY KEY (movement_id, lot_id),
 FOREIGN KEY (lot_id, tenant_id, business_id) REFERENCES core10.inventory_lots_v1(id, tenant_id, business_id),
 FOREIGN KEY (location_id, tenant_id, business_id, site_id) REFERENCES core10.stock_locations(id, tenant_id, business_id, site_id),
 FOREIGN KEY (item_id, tenant_id, business_id) REFERENCES core10.items(id, tenant_id, business_id)
);
CREATE INDEX stock_movement_lots_loc_ix ON core10.stock_movement_lots_v1 (location_id, item_id, lot_id);
CREATE INDEX stock_movement_lots_lot_ix ON core10.stock_movement_lots_v1 (lot_id, location_id);
-- Append-only like the ledger it breaks down.
CREATE FUNCTION core10._stock_movement_lots_immutable_v1() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $$
BEGIN RAISE EXCEPTION 'stock_movement_lots_immutable' USING ERRCODE='42501'; END $$;
CREATE TRIGGER stock_movement_lots_immutable_v1 BEFORE UPDATE OR DELETE ON core10.stock_movement_lots_v1
 FOR EACH ROW EXECUTE FUNCTION core10._stock_movement_lots_immutable_v1();
CREATE TRIGGER stock_movement_lots_truncate_v1 BEFORE TRUNCATE ON core10.stock_movement_lots_v1
 FOR EACH STATEMENT EXECUTE FUNCTION core10._stock_movement_lots_immutable_v1();

-- Derived lot balance (no stored quantity).
CREATE VIEW core10.stock_lot_balances_v1 WITH (security_invoker=true) AS
 SELECT ml.tenant_id, ml.business_id, ml.site_id, ml.location_id, ml.item_id, ml.lot_id,
  sum(ml.quantity)::numeric(15,3) AS on_hand
 FROM core10.stock_movement_lots_v1 ml
 GROUP BY ml.tenant_id, ml.business_id, ml.site_id, ml.location_id, ml.item_id, ml.lot_id;

-- Location balance vs its lot breakdown: untracked = on_hand - sum(lots) must be >= 0 and no lot below 0.
CREATE VIEW core10.inventory_lot_reconciliation_v1 WITH (security_invoker=true) AS
 SELECT b.tenant_id, b.business_id, b.site_id, b.location_id, b.item_id, b.on_hand,
  coalesce(l.lot_units,0)::numeric(15,3) AS lot_units, (b.on_hand-coalesce(l.lot_units,0))::numeric(15,3) AS untracked,
  coalesce(l.negative_lots,0) AS negative_lots,
  (b.on_hand>=coalesce(l.lot_units,0) AND coalesce(l.negative_lots,0)=0) AS reconciled
 FROM core10.stock_balances_v1 b
 LEFT JOIN (SELECT location_id, item_id, sum(on_hand) AS lot_units, count(*) FILTER (WHERE on_hand<0) AS negative_lots
   FROM core10.stock_lot_balances_v1 GROUP BY location_id, item_id) l
  ON l.location_id=b.location_id AND l.item_id=b.item_id;

-- ---------- lot-aware commands ----------
ALTER TABLE core10.inventory_commands_v1 ADD COLUMN lot_id bigint;
ALTER TABLE core10.inventory_commands_v1 ADD CONSTRAINT inventory_commands_v1_lot_fk_v1
 FOREIGN KEY (lot_id, tenant_id, business_id) REFERENCES core10.inventory_lots_v1(id, tenant_id, business_id);
CREATE INDEX inventory_commands_lot_ix ON core10.inventory_commands_v1 (lot_id) WHERE lot_id IS NOT NULL;

-- ---------- genealogy and recall (A058 model on the canonical lot master) ----------
CREATE TABLE core10.inventory_lot_links_v1 (
 tenant_id bigint NOT NULL, business_id bigint NOT NULL,
 parent_lot_id bigint NOT NULL, child_lot_id bigint NOT NULL,
 created_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY (parent_lot_id, child_lot_id), CHECK (parent_lot_id<>child_lot_id),
 FOREIGN KEY (parent_lot_id, tenant_id, business_id) REFERENCES core10.inventory_lots_v1(id, tenant_id, business_id),
 FOREIGN KEY (child_lot_id, tenant_id, business_id) REFERENCES core10.inventory_lots_v1(id, tenant_id, business_id)
);
CREATE INDEX inventory_lot_links_child_ix ON core10.inventory_lot_links_v1 (child_lot_id);

CREATE TABLE core10.inventory_lot_recalls_v1 (
 id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, root_lot_id bigint NOT NULL,
 severity text NOT NULL CHECK (severity IN ('internal','customer','critical')),
 reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 5 AND 1000),
 status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','closed')),
 request_key text NOT NULL CHECK (request_key ~ '^[A-Za-z0-9_-]{8,100}$'),
 created_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 closed_by uuid, closed_at timestamptz, close_note text CHECK (close_note IS NULL OR length(close_note)<=500),
 UNIQUE (business_id, request_key), UNIQUE (id, tenant_id, business_id),
 FOREIGN KEY (root_lot_id, tenant_id, business_id) REFERENCES core10.inventory_lots_v1(id, tenant_id, business_id),
 CHECK ((status='active' AND closed_by IS NULL AND closed_at IS NULL) OR (status='closed' AND closed_by IS NOT NULL AND closed_at IS NOT NULL))
);
CREATE UNIQUE INDEX inventory_lot_recalls_active_ux ON core10.inventory_lot_recalls_v1 (root_lot_id) WHERE status='active';
CREATE INDEX inventory_lot_recalls_business_ix ON core10.inventory_lot_recalls_v1 (business_id, id DESC);

CREATE TABLE core10.inventory_lot_recall_lots_v1 (
 recall_id bigint NOT NULL, tenant_id bigint NOT NULL, business_id bigint NOT NULL, lot_id bigint NOT NULL,
 depth integer NOT NULL CHECK (depth BETWEEN 0 AND 100),
 PRIMARY KEY (recall_id, lot_id),
 FOREIGN KEY (recall_id, tenant_id, business_id) REFERENCES core10.inventory_lot_recalls_v1(id, tenant_id, business_id),
 FOREIGN KEY (lot_id, tenant_id, business_id) REFERENCES core10.inventory_lots_v1(id, tenant_id, business_id)
);
CREATE INDEX inventory_lot_recall_lots_lot_ix ON core10.inventory_lot_recall_lots_v1 (lot_id);

-- Request ledger for lot operations (pattern of procurement_requests_v1).
CREATE TABLE core10.inventory_lot_requests_v1 (
 business_id bigint NOT NULL, request_key text NOT NULL CHECK (request_key ~ '^[A-Za-z0-9_-]{8,100}$'),
 tenant_id bigint NOT NULL, actor_id uuid NOT NULL,
 action text NOT NULL CHECK (action IN ('lot_hold','lot_release','recall_start','recall_close','lot_link')),
 entity_id bigint NOT NULL, intent_sha256 text NOT NULL CHECK (intent_sha256 ~ '^[0-9a-f]{64}$'),
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY (business_id, request_key),
 FOREIGN KEY (business_id, tenant_id) REFERENCES core10.businesses(id, tenant_id)
);

ALTER TABLE core10.stock_movement_lots_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE core10.inventory_lot_links_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE core10.inventory_lot_recalls_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE core10.inventory_lot_recall_lots_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE core10.inventory_lot_requests_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON core10.stock_movement_lots_v1, core10.inventory_lot_links_v1, core10.inventory_lot_recalls_v1,
 core10.inventory_lot_recall_lots_v1, core10.inventory_lot_requests_v1 FROM PUBLIC, authenticated;
REVOKE ALL ON core10.stock_lot_balances_v1, core10.inventory_lot_reconciliation_v1 FROM PUBLIC, authenticated;

-- ---------- engine helpers (internal) ----------
-- NULL = usable; otherwise why the lot may not be issued (recall wins over status).
CREATE FUNCTION core10._lot_block_reason_v1(p_lot bigint) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
 SELECT CASE WHEN EXISTS(SELECT 1 FROM core10.inventory_lot_recall_lots_v1 r WHERE r.lot_id=l.id) THEN 'lot_recalled'
  WHEN l.status='held' THEN 'lot_held' WHEN l.status='rejected' THEN 'lot_rejected' END
 FROM core10.inventory_lots_v1 l WHERE l.id=p_lot
$$;

CREATE FUNCTION core10._lot_on_hand_v1(p_location bigint, p_item bigint, p_lot bigint) RETURNS numeric
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
 SELECT coalesce(sum(quantity),0)::numeric(15,3) FROM core10.stock_movement_lots_v1
 WHERE location_id=p_location AND item_id=p_item AND lot_id=p_lot
$$;

-- Lot named by the source document of a server-built request key, or NULL.
-- {lot_id, allow_blocked (write-off / supplier return / receipt), block_expired (issue / transfer)}.
CREATE FUNCTION core10._stock_movement_lot_v1(p_business bigint, p_item bigint, p_request text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE m text[]; v_lot bigint; v_kind text;
BEGIN
 IF p_request ~ '^c10-inv-cmd-[0-9]{1,18}$' THEN
  SELECT c.lot_id, c.kind INTO v_lot, v_kind FROM core10.inventory_commands_v1 c
   WHERE c.id=substr(p_request,13)::bigint AND c.business_id=p_business AND c.item_id=p_item;
  IF v_lot IS NULL THEN RETURN NULL; END IF;
  RETURN jsonb_build_object('lot_id',v_lot,'allow_blocked',v_kind IN ('adjust_out','receive','adjust_in'),
   'block_expired',v_kind IN ('issue','transfer'));
 END IF;
 m := regexp_match(p_request, '^c10-grn-([0-9]{1,18})-([0-9]{1,9})$');
 IF m IS NOT NULL THEN
  SELECT lt.id INTO v_lot FROM core10.goods_receipt_lines_v1 gl
   JOIN core10.inventory_lots_v1 lt ON lt.business_id=gl.business_id AND lt.item_id=gl.item_id AND lt.lot_code=gl.lot_code
   WHERE gl.grn_id=m[1]::bigint AND gl.line_no=m[2]::int AND gl.business_id=p_business AND gl.item_id=p_item;
  RETURN CASE WHEN v_lot IS NULL THEN NULL ELSE jsonb_build_object('lot_id',v_lot,'allow_blocked',true,'block_expired',false) END;
 END IF;
 m := regexp_match(p_request, '^c10-ret-([0-9]{1,18})-([0-9]{1,9})$');
 IF m IS NOT NULL THEN
  SELECT rl.lot_id INTO v_lot FROM core10.supplier_return_lines_v1 rl
   WHERE rl.return_id=m[1]::bigint AND rl.line_no=m[2]::int AND rl.business_id=p_business AND rl.item_id=p_item;
  RETURN CASE WHEN v_lot IS NULL THEN NULL ELSE jsonb_build_object('lot_id',v_lot,'allow_blocked',true,'block_expired',false) END;
 END IF;
 RETURN NULL;
END $$;

-- Write the lot breakdown of one movement. MUST run in the posting transaction after the location/item balance row
-- was locked and the movement inserted; p_before = on_hand before this movement. Returns [{lot_id, quantity}] (signed).
CREATE FUNCTION core10._stock_lot_apply_v1(p_movement bigint, p_location bigint, p_item bigint, p_delta numeric,
 p_lot jsonb, p_before numeric) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_loc record; v_lot bigint := (p_lot->>'lot_id')::bigint; lt core10.inventory_lots_v1%ROWTYPE; v_why text;
 v_lots numeric; v_blocked numeric; v_need numeric; v_take numeric; r record; v_out jsonb := '[]';
BEGIN
 SELECT tenant_id,business_id,site_id INTO v_loc FROM core10.stock_locations WHERE id=p_location;
 IF v_lot IS NOT NULL THEN
  -- Share-lock the lot: a concurrent hold / release / recall waits, or this posting waits for it.
  SELECT * INTO lt FROM core10.inventory_lots_v1 WHERE id=v_lot FOR SHARE;
  IF NOT FOUND OR lt.tenant_id<>v_loc.tenant_id OR lt.business_id<>v_loc.business_id OR lt.item_id<>p_item
  THEN RAISE EXCEPTION 'lot_item_mismatch'; END IF;
  IF p_delta<0 THEN
   v_why := core10._lot_block_reason_v1(v_lot);
   IF v_why IS NOT NULL AND NOT coalesce((p_lot->>'allow_blocked')::boolean,false) THEN RAISE EXCEPTION '%', v_why; END IF;
   IF coalesce((p_lot->>'block_expired')::boolean,false) AND lt.expires_on IS NOT NULL AND lt.expires_on<current_date
   THEN RAISE EXCEPTION 'lot_expired'; END IF;
   IF core10._lot_on_hand_v1(p_location,p_item,v_lot)+p_delta<0 THEN RAISE EXCEPTION 'insufficient_lot_stock'; END IF;
  ELSIF EXISTS(SELECT 1 FROM core10.inventory_lot_recall_lots_v1 WHERE lot_id=v_lot)
   AND NOT coalesce((p_lot->>'allow_blocked')::boolean,false) THEN RAISE EXCEPTION 'lot_recalled';
  END IF;
  INSERT INTO core10.stock_movement_lots_v1(movement_id,lot_id,tenant_id,business_id,site_id,location_id,item_id,quantity)
  VALUES (p_movement,v_lot,v_loc.tenant_id,v_loc.business_id,v_loc.site_id,p_location,p_item,p_delta);
  RETURN jsonb_build_array(jsonb_build_object('lot_id',v_lot,'quantity',p_delta));
 END IF;
 IF p_delta>0 THEN RETURN v_out; END IF;
 -- Lot-less issue: no lot rows at this location/item = nothing to do (unchanged 0200 behaviour, one index probe).
 IF NOT EXISTS(SELECT 1 FROM core10.stock_movement_lots_v1 WHERE location_id=p_location AND item_id=p_item) THEN RETURN v_out; END IF;
 PERFORM 1 FROM core10.inventory_lots_v1 WHERE id IN
  (SELECT DISTINCT lot_id FROM core10.stock_movement_lots_v1 WHERE location_id=p_location AND item_id=p_item)
  ORDER BY id FOR SHARE;
 SELECT coalesce(sum(b.on_hand),0), coalesce(sum(b.on_hand) FILTER (WHERE core10._lot_block_reason_v1(b.lot_id) IS NOT NULL),0)
  INTO v_lots, v_blocked FROM core10.stock_lot_balances_v1 b WHERE b.location_id=p_location AND b.item_id=p_item;
 -- Held / rejected / recalled stock never leaves through a lot-less issue.
 IF -p_delta > p_before - v_blocked THEN RAISE EXCEPTION 'lot_blocked_stock'; END IF;
 v_need := -p_delta - (p_before - v_lots);   -- untracked stock goes first
 IF v_need <= 0 THEN RETURN v_out; END IF;
 FOR r IN SELECT b.lot_id, b.on_hand FROM core10.stock_lot_balances_v1 b JOIN core10.inventory_lots_v1 l ON l.id=b.lot_id
   WHERE b.location_id=p_location AND b.item_id=p_item AND b.on_hand>0 AND core10._lot_block_reason_v1(b.lot_id) IS NULL
   ORDER BY l.expires_on NULLS LAST, l.id LOOP
  EXIT WHEN v_need<=0;
  v_take := least(r.on_hand, v_need);
  INSERT INTO core10.stock_movement_lots_v1(movement_id,lot_id,tenant_id,business_id,site_id,location_id,item_id,quantity)
  VALUES (p_movement,r.lot_id,v_loc.tenant_id,v_loc.business_id,v_loc.site_id,p_location,p_item,-v_take);
  v_out := v_out || jsonb_build_array(jsonb_build_object('lot_id',r.lot_id,'quantity',-v_take));
  v_need := v_need - v_take;
 END LOOP;
 IF v_need>0 THEN RAISE EXCEPTION 'lot_breakdown_conflict'; END IF;
 RETURN v_out;
END $$;

-- ---------- the 0200 engine, now writing the lot breakdown (same checks, same order, same results) ----------
CREATE OR REPLACE FUNCTION core10.post_stock_event(
 p_location bigint,p_item bigint,p_delta numeric,p_request text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $$
DECLARE v_loc record; v_balance numeric(15,3); v_id bigint; v_prev record;
BEGIN
 IF core10.actor_uid() IS NULL OR
    p_delta IS NULL OR p_delta=0 OR
    p_delta::text IN('NaN','Infinity','-Infinity') OR
    p_delta<>round(p_delta,3) OR
    p_request IS NULL OR length(btrim(p_request))=0 OR
    left(p_request,13)='c10-transfer:' THEN
  RAISE EXCEPTION 'invalid_stock_event';
 END IF;
 SELECT tenant_id,business_id,site_id INTO v_loc
  FROM core10.stock_locations WHERE id=p_location;
 IF NOT FOUND OR NOT core10.can_site(
   v_loc.tenant_id,v_loc.business_id,v_loc.site_id,'stock.post') THEN
  RAISE EXCEPTION 'stock_post_not_authorized';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM core10.items
    WHERE id=p_item AND tenant_id=v_loc.tenant_id
      AND business_id=v_loc.business_id) THEN
  RAISE EXCEPTION 'stock_item_business_mismatch' USING ERRCODE='23503';
 END IF;

 -- Unique balance key serializes concurrent requests on this location/item.
 INSERT INTO core10.stock_balances_v1(
  tenant_id,business_id,site_id,location_id,item_id,on_hand)
 VALUES(v_loc.tenant_id,v_loc.business_id,v_loc.site_id,p_location,p_item,0)
 ON CONFLICT(location_id,item_id) DO NOTHING;

 SELECT on_hand INTO v_balance FROM core10.stock_balances_v1
  WHERE location_id=p_location AND item_id=p_item FOR UPDATE;

 -- The idempotency read must happen AFTER acquiring the balance lock.
 SELECT id,item_id,delta,created_by,transfer_id INTO v_prev
  FROM core10.stock_movements
  WHERE location_id=p_location AND request_key=p_request;
 IF FOUND THEN
  IF v_prev.item_id<>p_item OR v_prev.delta<>p_delta OR
     v_prev.created_by<>core10.actor_uid() OR v_prev.transfer_id IS NOT NULL THEN
   RAISE EXCEPTION 'idempotency_key_payload_conflict';
  END IF;
  RETURN v_prev.id;
 END IF;
 IF v_balance+p_delta<0 THEN RAISE EXCEPTION 'insufficient_stock'; END IF;
 UPDATE core10.stock_balances_v1 SET on_hand=on_hand+p_delta
  WHERE location_id=p_location AND item_id=p_item;
 INSERT INTO core10.stock_movements(
  tenant_id,business_id,site_id,location_id,item_id,delta,request_key,created_by)
 VALUES(v_loc.tenant_id,v_loc.business_id,v_loc.site_id,
   p_location,p_item,p_delta,p_request,core10.actor_uid())
 RETURNING id INTO v_id;
 -- 0209: lot breakdown of this movement under the same balance lock.
 PERFORM core10._stock_lot_apply_v1(v_id,p_location,p_item,p_delta,
  core10._stock_movement_lot_v1(v_loc.business_id,p_item,p_request),v_balance);
 RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION core10.transfer_stock_v1(
 p_source bigint,p_destination bigint,p_item bigint,p_quantity numeric,p_request text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $$
DECLARE v_source record; v_destination record;
 v_id bigint; v_prev record; v_on_hand numeric(15,3); v_out bigint; v_in bigint; v_lots jsonb; x jsonb;
BEGIN
 IF core10.actor_uid() IS NULL OR
  p_source IS NULL OR p_destination IS NULL OR p_source=p_destination OR
  p_quantity IS NULL OR p_quantity<=0 OR
  p_quantity::text IN('NaN','Infinity','-Infinity') OR
  p_quantity<>round(p_quantity,3) OR
  p_request IS NULL OR length(btrim(p_request))=0 THEN
  RAISE EXCEPTION 'invalid_transfer_request';
 END IF;
 SELECT tenant_id,business_id,site_id INTO v_source
  FROM core10.stock_locations WHERE id=p_source;
 SELECT tenant_id,business_id,site_id INTO v_destination
  FROM core10.stock_locations WHERE id=p_destination;
 IF v_source.tenant_id IS NULL OR v_destination.tenant_id IS NULL OR
   v_source.tenant_id<>v_destination.tenant_id OR
   v_source.business_id<>v_destination.business_id THEN
  RAISE EXCEPTION 'cross_business_transfer_forbidden';
 END IF;
 IF NOT core10.can_site(v_source.tenant_id,v_source.business_id,
      v_source.site_id,'stock.post')
    OR NOT core10.can_site(v_destination.tenant_id,v_destination.business_id,
      v_destination.site_id,'stock.post') THEN
  RAISE EXCEPTION 'transfer_not_authorized';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM core10.items WHERE id=p_item
       AND tenant_id=v_source.tenant_id AND business_id=v_source.business_id) THEN
  RAISE EXCEPTION 'stock_item_business_mismatch' USING ERRCODE='23503';
 END IF;

 -- Unique request key serializes exact retries; a failed transfer rolls
 -- back BOTH balance updates, BOTH journal rows and this header atomically.
 INSERT INTO core10.stock_transfers_v1(
  tenant_id,business_id,source_site_id,source_location_id,
  destination_site_id,destination_location_id,item_id,quantity,request_key,created_by)
 VALUES(v_source.tenant_id,v_source.business_id,v_source.site_id,p_source,
  v_destination.site_id,p_destination,p_item,p_quantity,p_request,core10.actor_uid())
 ON CONFLICT(tenant_id,business_id,request_key) DO NOTHING RETURNING id INTO v_id;
 IF v_id IS NULL THEN
  SELECT id,source_location_id,destination_location_id,item_id,quantity,created_by
   INTO v_prev FROM core10.stock_transfers_v1
   WHERE tenant_id=v_source.tenant_id AND business_id=v_source.business_id
    AND request_key=p_request;
  IF NOT FOUND OR v_prev.source_location_id<>p_source OR
     v_prev.destination_location_id<>p_destination OR
     v_prev.item_id<>p_item OR v_prev.quantity<>p_quantity OR
     v_prev.created_by<>core10.actor_uid() THEN
   RAISE EXCEPTION 'idempotency_key_payload_conflict';
  END IF;
  RETURN v_prev.id;
 END IF;

 INSERT INTO core10.stock_balances_v1(
    tenant_id,business_id,site_id,location_id,item_id,on_hand)
 VALUES(v_source.tenant_id,v_source.business_id,v_source.site_id,p_source,p_item,0),
       (v_destination.tenant_id,v_destination.business_id,
        v_destination.site_id,p_destination,p_item,0)
 ON CONFLICT(location_id,item_id) DO NOTHING;

 -- Globally ordered row locking avoids source/destination deadlocks.
 PERFORM 1 FROM core10.stock_balances_v1
  WHERE item_id=p_item AND location_id IN(p_source,p_destination)
  ORDER BY location_id FOR UPDATE;
 SELECT on_hand INTO v_on_hand FROM core10.stock_balances_v1
  WHERE location_id=p_source AND item_id=p_item;
 IF v_on_hand<p_quantity THEN RAISE EXCEPTION 'insufficient_stock'; END IF;

 UPDATE core10.stock_balances_v1 SET on_hand=on_hand-p_quantity
  WHERE location_id=p_source AND item_id=p_item;
 UPDATE core10.stock_balances_v1 SET on_hand=on_hand+p_quantity
  WHERE location_id=p_destination AND item_id=p_item;
 INSERT INTO core10.stock_movements(
  tenant_id,business_id,site_id,location_id,item_id,delta,request_key,created_by,transfer_id)
 VALUES
  (v_source.tenant_id,v_source.business_id,v_source.site_id,p_source,
   p_item,-p_quantity,'c10-transfer:'||v_id||':out',core10.actor_uid(),v_id)
 RETURNING id INTO v_out;
 INSERT INTO core10.stock_movements(
  tenant_id,business_id,site_id,location_id,item_id,delta,request_key,created_by,transfer_id)
 VALUES
  (v_destination.tenant_id,v_destination.business_id,v_destination.site_id,p_destination,
   p_item,p_quantity,'c10-transfer:'||v_id||':in',core10.actor_uid(),v_id)
 RETURNING id INTO v_in;
 -- 0209: the out-leg takes its lot (named, or untracked-then-FEFO); the in-leg carries the same lots.
 v_lots := core10._stock_lot_apply_v1(v_out,p_source,p_item,-p_quantity,
  core10._stock_movement_lot_v1(v_source.business_id,p_item,p_request),v_on_hand);
 FOR x IN SELECT value FROM jsonb_array_elements(v_lots) LOOP
  INSERT INTO core10.stock_movement_lots_v1(movement_id,lot_id,tenant_id,business_id,site_id,location_id,item_id,quantity)
  VALUES (v_in,(x->>'lot_id')::bigint,v_destination.tenant_id,v_destination.business_id,v_destination.site_id,
   p_destination,p_item,-(x->>'quantity')::numeric);
 END LOOP;
 RETURN v_id;
END $$;

-- ---------- backfill the breakdown of existing movements (id order, same rules, fail closed) ----------
DO $bf$
DECLARE m record; v_before numeric; v_lot jsonb; v_lots jsonb; x jsonb; v_out_lots jsonb := '{}';
BEGIN
 FOR m IN SELECT * FROM core10.stock_movements ORDER BY id LOOP
  IF m.transfer_id IS NOT NULL AND m.delta>0 THEN
   FOR x IN SELECT value FROM jsonb_array_elements(coalesce(v_out_lots->(m.transfer_id::text),'[]')) LOOP
    INSERT INTO core10.stock_movement_lots_v1(movement_id,lot_id,tenant_id,business_id,site_id,location_id,item_id,quantity)
    VALUES (m.id,(x->>'lot_id')::bigint,m.tenant_id,m.business_id,m.site_id,m.location_id,m.item_id,-(x->>'quantity')::numeric);
   END LOOP;
   CONTINUE;
  END IF;
  SELECT coalesce(sum(delta),0) INTO v_before FROM core10.stock_movements
   WHERE location_id=m.location_id AND item_id=m.item_id AND id<m.id;
  v_lot := NULL;
  SELECT jsonb_build_object('lot_id',gl.lot_id,'allow_blocked',true,'block_expired',false) INTO v_lot
   FROM core10.goods_receipt_lines_v1 gl WHERE gl.stock_movement_id=m.id AND gl.lot_id IS NOT NULL;
  IF v_lot IS NULL THEN
   SELECT jsonb_build_object('lot_id',rl.lot_id,'allow_blocked',true,'block_expired',false) INTO v_lot
    FROM core10.supplier_return_lines_v1 rl WHERE rl.stock_movement_id=m.id AND rl.lot_id IS NOT NULL;
  END IF;
  BEGIN
   v_lots := core10._stock_lot_apply_v1(m.id,m.location_id,m.item_id,m.delta,v_lot,v_before);
  EXCEPTION WHEN raise_exception THEN
   RAISE EXCEPTION 'INV_LOT_BACKFILL_CONFLICT:movement %:%', m.id, SQLERRM;
  END;
  IF m.transfer_id IS NOT NULL THEN v_out_lots := v_out_lots || jsonb_build_object(m.transfer_id::text, v_lots); END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM core10.inventory_lot_reconciliation_v1 WHERE NOT reconciled)
 THEN RAISE EXCEPTION 'INV_LOT_BACKFILL_UNRECONCILED'; END IF;
END $bf$;

-- ---------- 0202 payload / 0201 json carry the lot when there is one (unchanged otherwise) ----------
CREATE OR REPLACE FUNCTION core10._inventory_approval_payload_v1(c core10.inventory_commands_v1) RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,core10 AS $$
 SELECT jsonb_build_object('command_id',c.id,'business_id',c.business_id,'kind',c.kind,'item_id',c.item_id,
  'amount',c.quantity,'unit','base_qty','source_location',c.source_location,'source_site_id',c.source_site_id,
  'destination_location',c.destination_location,'destination_site_id',c.destination_site_id,'reason',c.reason,
  'version',c.version) || CASE WHEN c.lot_id IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('lot_id',c.lot_id) END
$$;

CREATE OR REPLACE FUNCTION core10._inventory_command_json_v1(c core10.inventory_commands_v1, p_replayed boolean) RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,core10 AS $$
 SELECT jsonb_build_object('command_id',c.id,'business_id',c.business_id,'kind',c.kind,'status',c.status,
  'version',c.version,'item_id',c.item_id,'quantity',c.quantity,'source_location',c.source_location,
  'source_site_id',c.source_site_id,'destination_location',c.destination_location,
  'destination_site_id',c.destination_site_id,'reason',c.reason,'stock_ref',c.stock_ref,
  'created_by',c.created_by,'created_at',c.created_at,'confirmed_by',c.confirmed_by,'posted_by',c.posted_by,
  'posted_at',c.posted_at,'cancelled_by',c.cancelled_by,'approval_request_id',c.approval_request_id,'replayed',p_replayed)
  || CASE WHEN c.lot_id IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('lot_id',c.lot_id) END
$$;

-- ---------- request ledger helpers for lot operations ----------
CREATE FUNCTION core10._lot_replay_v1(p_business bigint, p_key text, p_action text, p_sha text) RETURNS bigint
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE r core10.inventory_lot_requests_v1%ROWTYPE;
BEGIN
 IF p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,100}$' THEN RAISE EXCEPTION 'INV_INVALID_ACTION'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('c10lot:'||p_business||':'||p_key, 0));
 SELECT * INTO r FROM core10.inventory_lot_requests_v1 WHERE business_id=p_business AND request_key=p_key;
 IF NOT FOUND THEN RETURN NULL; END IF;
 IF r.actor_id<>core10.actor_uid() OR r.action<>p_action OR r.intent_sha256<>p_sha THEN RAISE EXCEPTION 'INV_REPLAY_CONFLICT'; END IF;
 RETURN r.entity_id;
END $$;

CREATE FUNCTION core10._lot_record_v1(p_tenant bigint, p_business bigint, p_key text, p_action text, p_entity bigint,
 p_sha text, p_payload jsonb) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
BEGIN
 INSERT INTO core10.inventory_lot_requests_v1(business_id,request_key,tenant_id,actor_id,action,entity_id,intent_sha256)
 VALUES (p_business,p_key,p_tenant,core10.actor_uid(),p_action,p_entity,p_sha);
 PERFORM core10._append_canonical_audit_v1(p_tenant,p_business,'inventory','lot-'||p_action||':'||p_key,
  'inventory.'||p_action,core10.actor_uid(),'inventory:'||p_business||':'||p_key,p_payload);
END $$;

CREATE FUNCTION core10._lot_json_v1(p_lot bigint) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
 SELECT jsonb_build_object('lot_id',l.id,'business_id',l.business_id,'item_id',l.item_id,'lot_code',l.lot_code,
  'status',l.status,'manufactured_on',l.manufactured_on,'expires_on',l.expires_on,
  'expired',coalesce(l.expires_on<current_date,false),'held_by',l.held_by,'held_at',l.held_at,'hold_reason',l.hold_reason,
  'recalled',EXISTS(SELECT 1 FROM core10.inventory_lot_recall_lots_v1 r WHERE r.lot_id=l.id),
  'blocked_reason',core10._lot_block_reason_v1(l.id))
 FROM core10.inventory_lots_v1 l WHERE l.id=p_lot
$$;

-- Sites the caller may read in one business (explicit site grants and denies win, as 0207 lot read / 0205).
CREATE FUNCTION core10._lot_readable_sites_v1(p_tenant bigint, p_business bigint, p_site bigint) RETURNS bigint[]
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
 SELECT coalesce(array_agg(s.id),'{}'::bigint[]) FROM core10.sites s
 WHERE s.tenant_id=p_tenant AND s.business_id=p_business AND (p_site IS NULL OR s.id=p_site)
   AND CASE WHEN s.id IN (SELECT gr.site_id FROM core10.site_grants gr WHERE gr.user_id=core10.actor_uid())
            THEN core10.can_site(p_tenant,p_business,s.id,'stock.read')
            ELSE core10.can_business(p_tenant,p_business) END
$$;

-- ---------- lot-aware stock command ----------
-- Same lifecycle and checks as create_inventory_command_v1 (called first: auth, shape, site permission, stock master
-- switch + kind feature per site, limits, request-key replay, audit) plus the lot: same business and item, Owner
-- Control inventory.lot_control on every touched site, and for issue / transfer a usable, unexpired lot with enough
-- lot stock at the source (re-checked by the engine when the command is posted). adjust_out may write off a held /
-- rejected / recalled lot. receive / adjust_in may add stock to a lot unless it is recalled.
CREATE FUNCTION core10.inventory_create_lot_command_v1(
 p_business bigint, p_kind text, p_source bigint, p_destination bigint,
 p_item bigint, p_quantity numeric, p_lot bigint, p_reason text, p_request text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_actor uuid := core10.actor_uid(); j jsonb; c core10.inventory_commands_v1%ROWTYPE;
 lt core10.inventory_lots_v1%ROWTYPE; s bigint; v_why text;
BEGIN
 IF p_lot IS NULL THEN RAISE EXCEPTION 'INV_LOT_REQUIRED'; END IF;
 -- Lock order lot -> audit chain head (as hold / recall / posting): share-lock the lot BEFORE the inner create appends
 -- canonical audit, else a concurrent hold of this lot deadlocks. Authorize before locking.
 SELECT * INTO lt FROM core10.inventory_lots_v1 WHERE id=p_lot;
 IF FOUND AND lt.business_id=p_business AND core10.can_see_business(lt.tenant_id,lt.business_id) THEN
  PERFORM 1 FROM core10.inventory_lots_v1 WHERE id=p_lot FOR SHARE;
 END IF;
 j := core10.create_inventory_command_v1(p_business,p_kind,p_source,p_destination,p_item,p_quantity,p_reason,p_request);
 SELECT * INTO c FROM core10.inventory_commands_v1 WHERE id=(j->>'command_id')::bigint FOR UPDATE;
 FOREACH s IN ARRAY array_remove(ARRAY[c.source_site_id, CASE WHEN c.destination_site_id IS DISTINCT FROM c.source_site_id
   THEN c.destination_site_id END], NULL) LOOP
  PERFORM core10.control_check_v1(c.business_id, 'inventory.lot_control', s);
 END LOOP;
 IF (j->>'replayed')::boolean THEN
  IF c.lot_id IS DISTINCT FROM p_lot THEN RAISE EXCEPTION 'INV_REPLAY_CONFLICT'; END IF;
  RETURN j || jsonb_build_object('lot',core10._lot_json_v1(c.lot_id));
 END IF;
 SELECT * INTO lt FROM core10.inventory_lots_v1 WHERE id=p_lot FOR SHARE;
 IF NOT FOUND OR lt.tenant_id<>c.tenant_id OR lt.business_id<>c.business_id OR lt.item_id<>c.item_id
 THEN RAISE EXCEPTION 'INV_LOT_SCOPE'; END IF;
 v_why := core10._lot_block_reason_v1(p_lot);
 IF c.kind IN ('issue','transfer') THEN
  IF v_why IS NOT NULL THEN RAISE EXCEPTION 'INV_%', upper(v_why); END IF;
  IF lt.expires_on IS NOT NULL AND lt.expires_on<current_date THEN RAISE EXCEPTION 'INV_LOT_EXPIRED'; END IF;
 ELSIF c.kind IN ('receive','adjust_in') AND v_why='lot_recalled' THEN RAISE EXCEPTION 'INV_LOT_RECALLED';
 END IF;
 IF c.kind IN ('issue','transfer','adjust_out') AND core10._lot_on_hand_v1(c.source_location,c.item_id,p_lot)<c.quantity
 THEN RAISE EXCEPTION 'INV_INSUFFICIENT_LOT_STOCK'; END IF;
 UPDATE core10.inventory_commands_v1 SET lot_id=p_lot WHERE id=c.id AND status='draft' AND lot_id IS NULL RETURNING * INTO c;
 IF NOT FOUND THEN RAISE EXCEPTION 'INV_INVALID_TRANSITION'; END IF;
 PERFORM core10._append_canonical_audit_v1(c.tenant_id,c.business_id,'inventory','command:'||c.id||':lot','inventory.command_lot_set',
  v_actor,'inventory:'||c.business_id||':'||p_request||':lot',
  jsonb_build_object('command_id',c.id,'kind',c.kind,'item_id',c.item_id,'lot_id',p_lot,'lot_code',lt.lot_code,'quantity',c.quantity));
 RETURN core10._inventory_command_json_v1(c,false) || jsonb_build_object('lot',core10._lot_json_v1(p_lot));
END $$;

-- ---------- hold / release ----------
-- A manager or owner of the business holds a released lot (no named or lot-less issue / transfer of its stock) or
-- releases a held one. A recalled or rejected lot cannot be released.
CREATE FUNCTION core10.inventory_lot_hold_v1(p_lot bigint, p_action text, p_reason text, p_key text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_actor uuid := core10.actor_uid(); lt core10.inventory_lots_v1%ROWTYPE; ctl jsonb; v_sha text; v_id bigint;
 v_reason text := nullif(btrim(p_reason),''); v_from text;
BEGIN
 IF v_actor IS NULL OR p_action IS NULL OR p_action NOT IN ('hold','release') THEN RAISE EXCEPTION 'INV_INVALID_ACTION'; END IF;
 SELECT * INTO lt FROM core10.inventory_lots_v1 WHERE id=p_lot;
 IF NOT FOUND OR NOT core10.can_see_business(lt.tenant_id,lt.business_id) THEN RAISE EXCEPTION 'INV_SCOPE'; END IF;
 IF NOT core10.can_manage(lt.tenant_id,lt.business_id) THEN RAISE EXCEPTION 'INV_PERMISSION_DENIED'; END IF;
 SELECT * INTO lt FROM core10.inventory_lots_v1 WHERE id=p_lot FOR UPDATE;
 IF NOT core10.can_manage(lt.tenant_id,lt.business_id) THEN RAISE EXCEPTION 'INV_PERMISSION_DENIED'; END IF;
 ctl := core10.control_check_v1(lt.business_id, 'inventory.lot_control', NULL);
 v_sha := encode(sha256(convert_to(jsonb_build_object('lot',p_lot,'a',p_action,'r',v_reason)::text,'UTF8')),'hex');
 v_id := core10._lot_replay_v1(lt.business_id,p_key,'lot_'||p_action,v_sha);
 IF v_id IS NOT NULL THEN RETURN core10._lot_json_v1(v_id) || '{"replayed":true}'; END IF;
 IF v_reason IS NOT NULL AND length(v_reason) NOT BETWEEN 3 AND 300 THEN RAISE EXCEPTION 'INV_REASON_INVALID'; END IF;
 IF (ctl->'params'->>'reason_required')::boolean AND v_reason IS NULL THEN RAISE EXCEPTION 'INV_REASON_REQUIRED'; END IF;
 v_from := lt.status;
 IF p_action='hold' THEN
  IF lt.status<>'released' THEN RAISE EXCEPTION 'INV_INVALID_TRANSITION'; END IF;
  UPDATE core10.inventory_lots_v1 SET status='held',held_by=v_actor,held_at=now(),hold_reason=v_reason WHERE id=p_lot;
 ELSE
  IF EXISTS(SELECT 1 FROM core10.inventory_lot_recall_lots_v1 WHERE lot_id=p_lot) THEN RAISE EXCEPTION 'INV_LOT_RECALLED'; END IF;
  IF lt.status<>'held' THEN RAISE EXCEPTION 'INV_INVALID_TRANSITION'; END IF;
  IF (ctl->'params'->>'separate_releaser')::boolean AND lt.held_by=v_actor THEN RAISE EXCEPTION 'INV_SAME_ACTOR'; END IF;
  UPDATE core10.inventory_lots_v1 SET status='released',held_by=NULL,held_at=NULL,hold_reason=NULL WHERE id=p_lot;
 END IF;
 PERFORM core10._lot_record_v1(lt.tenant_id,lt.business_id,p_key,'lot_'||p_action,p_lot,v_sha,
  jsonb_build_object('lot_id',p_lot,'lot_code',lt.lot_code,'item_id',lt.item_id,'from_status',v_from,'reason',v_reason,
   'on_hand',(SELECT coalesce(sum(quantity),0) FROM core10.stock_movement_lots_v1 WHERE lot_id=p_lot)));
 RETURN core10._lot_json_v1(p_lot) || '{"replayed":false}';
END $$;

-- ---------- genealogy ----------
-- Record that p_child was made from p_parent (same business). Cycles and links touching a recalled lot are refused.
CREATE FUNCTION core10.inventory_lot_link_v1(p_parent bigint, p_child bigint, p_key text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_actor uuid := core10.actor_uid(); pa core10.inventory_lots_v1%ROWTYPE; ch core10.inventory_lots_v1%ROWTYPE;
 v_sha text; v_id bigint;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'INV_SCOPE'; END IF;
 SELECT * INTO pa FROM core10.inventory_lots_v1 WHERE id=p_parent;
 SELECT * INTO ch FROM core10.inventory_lots_v1 WHERE id=p_child;
 IF pa.id IS NULL OR ch.id IS NULL OR NOT core10.can_see_business(pa.tenant_id,pa.business_id)
  OR ch.tenant_id<>pa.tenant_id OR ch.business_id<>pa.business_id THEN RAISE EXCEPTION 'INV_SCOPE'; END IF;
 IF NOT core10.can_manage(pa.tenant_id,pa.business_id) THEN RAISE EXCEPTION 'INV_PERMISSION_DENIED'; END IF;
 PERFORM core10.control_check_v1(pa.business_id, 'inventory.lot_recall', NULL);
 v_sha := encode(sha256(convert_to(jsonb_build_object('p',p_parent,'c',p_child)::text,'UTF8')),'hex');
 v_id := core10._lot_replay_v1(pa.business_id,p_key,'lot_link',v_sha);
 IF v_id IS NOT NULL THEN RETURN jsonb_build_object('parent_lot_id',p_parent,'child_lot_id',p_child,'replayed',true); END IF;
 -- One business-wide graph lock: concurrent links cannot build a cycle, recalls see a stable graph.
 PERFORM pg_advisory_xact_lock(hashtextextended('c10lotgraph:'||pa.business_id, 0));
 IF p_parent=p_child THEN RAISE EXCEPTION 'INV_LOT_GENEALOGY_CYCLE'; END IF;
 IF EXISTS(SELECT 1 FROM core10.inventory_lot_recall_lots_v1 WHERE lot_id IN (p_parent,p_child)) THEN RAISE EXCEPTION 'INV_LOT_RECALLED'; END IF;
 IF EXISTS(SELECT 1 FROM core10.inventory_lot_links_v1 WHERE parent_lot_id=p_parent AND child_lot_id=p_child) THEN RAISE EXCEPTION 'INV_LOT_LINK_EXISTS'; END IF;
 IF EXISTS(WITH RECURSIVE d(id) AS (SELECT p_child UNION SELECT k.child_lot_id FROM core10.inventory_lot_links_v1 k JOIN d ON k.parent_lot_id=d.id)
   SELECT 1 FROM d WHERE id=p_parent) THEN RAISE EXCEPTION 'INV_LOT_GENEALOGY_CYCLE'; END IF;
 INSERT INTO core10.inventory_lot_links_v1(tenant_id,business_id,parent_lot_id,child_lot_id,created_by)
 VALUES (pa.tenant_id,pa.business_id,p_parent,p_child,v_actor);
 PERFORM core10._lot_record_v1(pa.tenant_id,pa.business_id,p_key,'lot_link',p_child,v_sha,
  jsonb_build_object('parent_lot_id',p_parent,'parent_lot_code',pa.lot_code,'child_lot_id',p_child,'child_lot_code',ch.lot_code));
 RETURN jsonb_build_object('parent_lot_id',p_parent,'child_lot_id',p_child,'replayed',false);
END $$;

-- ---------- recall ----------
-- Where a recall's lots are now: lot balances > 0 at readable sites, per lot and location (<= 500 rows), totals, and
-- the posted receipts / supplier returns that brought them in or sent them back.
CREATE FUNCTION core10._lot_recall_json_v1(p_recall bigint, p_sites bigint[]) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
 SELECT jsonb_build_object('recall_id',r.id,'business_id',r.business_id,'root_lot_id',r.root_lot_id,'severity',r.severity,
  'reason',r.reason,'status',r.status,'created_by',r.created_by,'created_at',r.created_at,'closed_by',r.closed_by,
  'closed_at',r.closed_at,'close_note',r.close_note,
  'lots',coalesce((SELECT jsonb_agg(jsonb_build_object('lot_id',l.id,'lot_code',l.lot_code,'item_id',l.item_id,'depth',rl.depth,
     'expires_on',l.expires_on,'status',l.status) ORDER BY rl.depth,l.id)
    FROM core10.inventory_lot_recall_lots_v1 rl JOIN core10.inventory_lots_v1 l ON l.id=rl.lot_id WHERE rl.recall_id=r.id),'[]'::jsonb),
  'locations',coalesce((SELECT jsonb_agg(x.j ORDER BY x.site_id,x.location_id,x.lot_id) FROM (
     SELECT b.site_id,b.location_id,b.lot_id,jsonb_build_object('site_id',b.site_id,'site_label',s.label,'site_kind',s.kind,
      'location_id',b.location_id,'location_code',sl.code,'lot_id',b.lot_id,'item_id',b.item_id,'on_hand',b.on_hand) AS j
     FROM core10.stock_lot_balances_v1 b JOIN core10.inventory_lot_recall_lots_v1 rl ON rl.lot_id=b.lot_id AND rl.recall_id=r.id
     JOIN core10.sites s ON s.id=b.site_id JOIN core10.stock_locations sl ON sl.id=b.location_id
     WHERE b.on_hand<>0 AND b.site_id=ANY(p_sites) ORDER BY b.site_id,b.location_id,b.lot_id LIMIT 500) x),'[]'::jsonb),
  'remaining_on_hand',(SELECT coalesce(sum(b.on_hand),0) FROM core10.stock_lot_balances_v1 b
     JOIN core10.inventory_lot_recall_lots_v1 rl ON rl.lot_id=b.lot_id AND rl.recall_id=r.id WHERE b.site_id=ANY(p_sites)),
  'receipts',coalesce((SELECT jsonb_agg(jsonb_build_object('grn_id',g.id,'po_id',g.po_id,'site_id',g.site_id,'line_no',gl.line_no,
     'lot_id',gl.lot_id,'accepted_qty',gl.accepted_qty,'returned_qty',gl.returned_qty,'posted_at',g.posted_at) ORDER BY g.id,gl.line_no)
    FROM core10.goods_receipt_lines_v1 gl JOIN core10.goods_receipts_v1 g ON g.id=gl.grn_id
    JOIN core10.inventory_lot_recall_lots_v1 rl ON rl.lot_id=gl.lot_id AND rl.recall_id=r.id
    WHERE g.status='posted' AND g.site_id=ANY(p_sites)),'[]'::jsonb))
 FROM core10.inventory_lot_recalls_v1 r WHERE r.id=p_recall
$$;

CREATE FUNCTION core10.inventory_lot_start_recall_v1(p_lot bigint, p_severity text, p_reason text, p_key text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_actor uuid := core10.actor_uid(); lt core10.inventory_lots_v1%ROWTYPE; ctl jsonb; v_sha text; v_id bigint;
 v_gen boolean; v_n int;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'INV_SCOPE'; END IF;
 SELECT * INTO lt FROM core10.inventory_lots_v1 WHERE id=p_lot;
 IF NOT FOUND OR NOT core10.can_see_business(lt.tenant_id,lt.business_id) THEN RAISE EXCEPTION 'INV_SCOPE'; END IF;
 IF NOT core10.can_manage(lt.tenant_id,lt.business_id) THEN RAISE EXCEPTION 'INV_PERMISSION_DENIED'; END IF;
 ctl := core10.control_check_v1(lt.business_id, 'inventory.lot_recall', NULL);
 v_sha := encode(sha256(convert_to(jsonb_build_object('lot',p_lot,'s',p_severity,'r',p_reason)::text,'UTF8')),'hex');
 v_id := core10._lot_replay_v1(lt.business_id,p_key,'recall_start',v_sha);
 IF v_id IS NOT NULL THEN
  RETURN core10._lot_recall_json_v1(v_id,core10._lot_readable_sites_v1(lt.tenant_id,lt.business_id,NULL)) || '{"replayed":true}';
 END IF;
 IF p_severity IS NULL OR p_severity NOT IN ('internal','customer','critical') OR p_reason IS NULL
  OR length(btrim(p_reason)) NOT BETWEEN 5 AND 1000 THEN RAISE EXCEPTION 'INV_INVALID_RECALL'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('c10lotgraph:'||lt.business_id, 0));
 IF EXISTS(SELECT 1 FROM core10.inventory_lot_recalls_v1 WHERE root_lot_id=p_lot AND status='active') THEN RAISE EXCEPTION 'INV_RECALL_ACTIVE'; END IF;
 v_gen := coalesce((ctl->'params'->>'include_genealogy')::boolean,true);
 INSERT INTO core10.inventory_lot_recalls_v1(tenant_id,business_id,root_lot_id,severity,reason,request_key,created_by)
 VALUES (lt.tenant_id,lt.business_id,p_lot,p_severity,btrim(p_reason),p_key,v_actor) RETURNING id INTO v_id;
 -- Root plus every downstream lot (when genealogy is on), shallowest depth first.
 INSERT INTO core10.inventory_lot_recall_lots_v1(recall_id,tenant_id,business_id,lot_id,depth)
 WITH RECURSIVE d(id,depth) AS (
  SELECT p_lot,0
  UNION SELECT k.child_lot_id,d.depth+1 FROM core10.inventory_lot_links_v1 k JOIN d ON k.parent_lot_id=d.id
   WHERE v_gen AND k.business_id=lt.business_id AND d.depth<100)
 SELECT v_id,lt.tenant_id,lt.business_id,id,min(depth) FROM d GROUP BY id;
 -- Lock the impacted lots (id order): in-flight postings of them finish first, later ones see the recall.
 PERFORM 1 FROM core10.inventory_lots_v1 WHERE id IN (SELECT lot_id FROM core10.inventory_lot_recall_lots_v1 WHERE recall_id=v_id)
  ORDER BY id FOR UPDATE;
 SELECT count(*) INTO v_n FROM core10.inventory_lot_recall_lots_v1 WHERE recall_id=v_id;
 PERFORM core10._lot_record_v1(lt.tenant_id,lt.business_id,p_key,'recall_start',v_id,v_sha,
  jsonb_build_object('recall_id',v_id,'root_lot_id',p_lot,'lot_code',lt.lot_code,'severity',p_severity,'reason',btrim(p_reason),
   'affected_lots',v_n,'on_hand',(SELECT coalesce(sum(ml.quantity),0) FROM core10.stock_movement_lots_v1 ml
     WHERE ml.lot_id IN (SELECT lot_id FROM core10.inventory_lot_recall_lots_v1 WHERE recall_id=v_id))));
 RETURN core10._lot_recall_json_v1(v_id,core10._lot_readable_sites_v1(lt.tenant_id,lt.business_id,NULL)) || '{"replayed":false}';
END $$;

-- Close an active recall. With close_requires_zero_stock (default) every recalled lot must be empty everywhere
-- (written off with a lot adjust_out or returned to the supplier). Recalled lots stay blocked after closing.
CREATE FUNCTION core10.inventory_lot_close_recall_v1(p_recall bigint, p_note text, p_key text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_actor uuid := core10.actor_uid(); r core10.inventory_lot_recalls_v1%ROWTYPE; ctl jsonb; v_sha text; v_id bigint;
 v_left numeric;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'INV_SCOPE'; END IF;
 SELECT * INTO r FROM core10.inventory_lot_recalls_v1 WHERE id=p_recall;
 IF NOT FOUND OR NOT core10.can_see_business(r.tenant_id,r.business_id) THEN RAISE EXCEPTION 'INV_SCOPE'; END IF;
 IF NOT core10.can_manage(r.tenant_id,r.business_id) THEN RAISE EXCEPTION 'INV_PERMISSION_DENIED'; END IF;
 SELECT * INTO r FROM core10.inventory_lot_recalls_v1 WHERE id=p_recall FOR UPDATE;
 IF NOT core10.can_manage(r.tenant_id,r.business_id) THEN RAISE EXCEPTION 'INV_PERMISSION_DENIED'; END IF;
 ctl := core10.control_check_v1(r.business_id, 'inventory.lot_recall', NULL);
 v_sha := encode(sha256(convert_to(jsonb_build_object('rc',p_recall,'n',p_note)::text,'UTF8')),'hex');
 v_id := core10._lot_replay_v1(r.business_id,p_key,'recall_close',v_sha);
 IF v_id IS NOT NULL THEN
  RETURN core10._lot_recall_json_v1(v_id,core10._lot_readable_sites_v1(r.tenant_id,r.business_id,NULL)) || '{"replayed":true}';
 END IF;
 IF r.status<>'active' THEN RAISE EXCEPTION 'INV_INVALID_TRANSITION'; END IF;
 IF p_note IS NOT NULL AND length(p_note)>500 THEN RAISE EXCEPTION 'INV_REASON_INVALID'; END IF;
 -- Lock the recalled lots so no posting of them interleaves with the stock check.
 PERFORM 1 FROM core10.inventory_lots_v1 WHERE id IN (SELECT lot_id FROM core10.inventory_lot_recall_lots_v1 WHERE recall_id=r.id)
  ORDER BY id FOR UPDATE;
 SELECT coalesce(sum(ml.quantity),0) INTO v_left FROM core10.stock_movement_lots_v1 ml
  WHERE ml.lot_id IN (SELECT lot_id FROM core10.inventory_lot_recall_lots_v1 WHERE recall_id=r.id);
 IF v_left<>0 AND coalesce((ctl->'params'->>'close_requires_zero_stock')::boolean,true) THEN
  RAISE EXCEPTION 'INV_RECALL_STOCK_REMAINING:%', v_left;
 END IF;
 UPDATE core10.inventory_lot_recalls_v1 SET status='closed',closed_by=v_actor,closed_at=now(),close_note=nullif(btrim(p_note),'')
  WHERE id=r.id;
 PERFORM core10._lot_record_v1(r.tenant_id,r.business_id,p_key,'recall_close',r.id,v_sha,
  jsonb_build_object('recall_id',r.id,'root_lot_id',r.root_lot_id,'remaining_on_hand',v_left,'note',nullif(btrim(p_note),'')));
 RETURN core10._lot_recall_json_v1(r.id,core10._lot_readable_sites_v1(r.tenant_id,r.business_id,NULL)) || '{"replayed":false}';
END $$;

-- ---------- reads (STABLE, scoped) ----------
CREATE FUNCTION core10.inventory_lot_recall_v1(p_recall bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE r core10.inventory_lot_recalls_v1%ROWTYPE;
BEGIN
 SELECT * INTO r FROM core10.inventory_lot_recalls_v1 WHERE id=p_recall;
 IF core10.actor_uid() IS NULL OR NOT FOUND OR NOT core10.can_see_business(r.tenant_id,r.business_id) THEN RAISE EXCEPTION 'INV_SCOPE'; END IF;
 RETURN core10._lot_recall_json_v1(r.id,core10._lot_readable_sites_v1(r.tenant_id,r.business_id,NULL));
END $$;

-- Lot balances of one business at the sites the caller may read; keyset on (location_id, lot_id), pages <= 200.
CREATE FUNCTION core10.inventory_list_lot_balances_v1(p_business bigint, p_site bigint DEFAULT NULL, p_item bigint DEFAULT NULL,
 p_after_location bigint DEFAULT NULL, p_after_lot bigint DEFAULT NULL, p_limit integer DEFAULT 100) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint; v_limit int := least(greatest(coalesce(p_limit,100),1),200); v_rows jsonb; v_sites bigint[];
BEGIN
 SELECT tenant_id INTO t FROM core10.businesses WHERE id=p_business;
 IF core10.actor_uid() IS NULL OR t IS NULL OR NOT core10.can_see_business(t,p_business) THEN RAISE EXCEPTION 'INV_SCOPE'; END IF;
 IF p_site IS NOT NULL AND NOT core10.can_site(t,p_business,p_site,'stock.read') THEN RAISE EXCEPTION 'INV_SCOPE'; END IF;
 IF (p_after_location IS NULL) <> (p_after_lot IS NULL) THEN RAISE EXCEPTION 'INV_INVALID_FILTER'; END IF;
 v_sites := core10._lot_readable_sites_v1(t,p_business,p_site);
 SELECT coalesce(jsonb_agg(q.r ORDER BY (q.r->>'location_id')::bigint,(q.r->>'lot_id')::bigint),'[]'::jsonb) INTO v_rows FROM (
  SELECT jsonb_build_object('site_id',b.site_id,'site_label',s.label,'location_id',b.location_id,'location_code',sl.code,
   'item_id',b.item_id,'sku',i.sku,'name_en',i.name_en,'name_bn',i.name_bn,'lot_id',b.lot_id,'lot_code',l.lot_code,
   'expires_on',l.expires_on,'days_to_expiry',CASE WHEN l.expires_on IS NOT NULL THEN l.expires_on-current_date END,
   'status',l.status,'blocked_reason',core10._lot_block_reason_v1(l.id),'on_hand',b.on_hand) AS r
  FROM core10.stock_lot_balances_v1 b
  JOIN core10.inventory_lots_v1 l ON l.id=b.lot_id JOIN core10.items i ON i.id=b.item_id
  JOIN core10.sites s ON s.id=b.site_id JOIN core10.stock_locations sl ON sl.id=b.location_id
  WHERE b.business_id=p_business AND b.tenant_id=t AND b.site_id=ANY(v_sites) AND b.on_hand<>0
    AND (p_item IS NULL OR b.item_id=p_item)
    AND (p_after_location IS NULL OR (b.location_id,b.lot_id)>(p_after_location,p_after_lot))
  ORDER BY b.location_id,b.lot_id LIMIT v_limit) q;
 RETURN jsonb_build_object('business_id',p_business,'site_id',p_site,'item_id',p_item,'as_of',current_date,'items',v_rows,'limit',v_limit,
  'next_after',CASE WHEN jsonb_array_length(v_rows)=v_limit THEN jsonb_build_object(
   'location_id',(v_rows->(v_limit-1)->>'location_id')::bigint,'lot_id',(v_rows->(v_limit-1)->>'lot_id')::bigint) END);
END $$;

-- FEFO pick suggestion for p_qty of one item at one site: released, unrecalled, unexpired lots with stock, earliest
-- expiry first (no expiry last), then lot, then location. Read only: nothing is reserved; posting re-checks everything.
CREATE FUNCTION core10.inventory_fefo_v1(p_business bigint, p_site bigint, p_item bigint, p_qty numeric) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint; v_lines jsonb; v_sug numeric; v_untracked numeric; v_excl jsonb;
BEGIN
 SELECT tenant_id INTO t FROM core10.businesses WHERE id=p_business;
 IF core10.actor_uid() IS NULL OR t IS NULL OR NOT core10.can_see_business(t,p_business)
  OR p_site IS NULL OR NOT core10.can_site(t,p_business,p_site,'stock.read') THEN RAISE EXCEPTION 'INV_SCOPE'; END IF;
 IF p_item IS NULL OR NOT EXISTS(SELECT 1 FROM core10.items WHERE id=p_item AND tenant_id=t AND business_id=p_business)
 THEN RAISE EXCEPTION 'INV_ITEM_SCOPE'; END IF;
 IF p_qty IS NULL OR p_qty::text IN ('NaN','Infinity','-Infinity') OR p_qty<=0 OR p_qty>1000000 OR p_qty<>round(p_qty,3)
 THEN RAISE EXCEPTION 'INV_INVALID_COMMAND'; END IF;
 WITH e AS (
  SELECT b.location_id, sl.code AS location_code, b.lot_id, l.lot_code, l.expires_on, b.on_hand AS available
  FROM core10.stock_lot_balances_v1 b JOIN core10.inventory_lots_v1 l ON l.id=b.lot_id
  JOIN core10.stock_locations sl ON sl.id=b.location_id
  WHERE b.business_id=p_business AND b.site_id=p_site AND b.item_id=p_item AND b.on_hand>0
    AND core10._lot_block_reason_v1(b.lot_id) IS NULL AND (l.expires_on IS NULL OR l.expires_on>=current_date)),
 r AS (SELECT e.*, coalesce(sum(e.available) OVER (ORDER BY e.expires_on NULLS LAST, e.lot_id, e.location_id
   ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),0) AS before FROM e)
 SELECT coalesce(jsonb_agg(jsonb_build_object('location_id',r.location_id,'location_code',r.location_code,'lot_id',r.lot_id,
   'lot_code',r.lot_code,'expires_on',r.expires_on,'days_to_expiry',CASE WHEN r.expires_on IS NOT NULL THEN r.expires_on-current_date END,
   'available',r.available,'suggested',greatest(least(r.available,p_qty-r.before),0))
   ORDER BY r.expires_on NULLS LAST, r.lot_id, r.location_id) FILTER (WHERE r.before<p_qty),'[]'::jsonb),
  coalesce(sum(greatest(least(r.available,p_qty-r.before),0)),0)
 INTO v_lines, v_sug FROM r;
 SELECT coalesce(sum(x.untracked),0) INTO v_untracked FROM core10.inventory_lot_reconciliation_v1 x
  WHERE x.business_id=p_business AND x.site_id=p_site AND x.item_id=p_item;
 SELECT jsonb_build_object(
   'held',coalesce(sum(b.on_hand) FILTER (WHERE core10._lot_block_reason_v1(b.lot_id) IN ('lot_held','lot_rejected')),0),
   'recalled',coalesce(sum(b.on_hand) FILTER (WHERE core10._lot_block_reason_v1(b.lot_id)='lot_recalled'),0),
   'expired',coalesce(sum(b.on_hand) FILTER (WHERE core10._lot_block_reason_v1(b.lot_id) IS NULL AND l.expires_on<current_date),0))
  INTO v_excl FROM core10.stock_lot_balances_v1 b JOIN core10.inventory_lots_v1 l ON l.id=b.lot_id
  WHERE b.business_id=p_business AND b.site_id=p_site AND b.item_id=p_item AND b.on_hand>0;
 RETURN jsonb_build_object('business_id',p_business,'site_id',p_site,'item_id',p_item,'requested',p_qty,'as_of',current_date,
  'lines',v_lines,'suggested_total',v_sug,'shortfall',greatest(p_qty-v_sug,0),'untracked_available',v_untracked,
  'excluded',v_excl,'reserved',false);
END $$;

REVOKE ALL ON FUNCTION core10._stock_movement_lots_immutable_v1(), core10._lot_block_reason_v1(bigint),
 core10._lot_on_hand_v1(bigint,bigint,bigint), core10._stock_movement_lot_v1(bigint,bigint,text),
 core10._stock_lot_apply_v1(bigint,bigint,bigint,numeric,jsonb,numeric),
 core10._lot_replay_v1(bigint,text,text,text), core10._lot_record_v1(bigint,bigint,text,text,bigint,text,jsonb),
 core10._lot_json_v1(bigint), core10._lot_readable_sites_v1(bigint,bigint,bigint), core10._lot_recall_json_v1(bigint,bigint[])
 FROM PUBLIC, authenticated;
REVOKE ALL ON FUNCTION core10.post_stock_event(bigint,bigint,numeric,text) FROM PUBLIC,authenticated;
REVOKE ALL ON FUNCTION core10.transfer_stock_v1(bigint,bigint,bigint,numeric,text) FROM PUBLIC,authenticated;
REVOKE ALL ON FUNCTION core10.inventory_create_lot_command_v1(bigint,text,bigint,bigint,bigint,numeric,bigint,text,text),
 core10.inventory_lot_hold_v1(bigint,text,text,text), core10.inventory_lot_link_v1(bigint,bigint,text),
 core10.inventory_lot_start_recall_v1(bigint,text,text,text), core10.inventory_lot_close_recall_v1(bigint,text,text),
 core10.inventory_lot_recall_v1(bigint), core10.inventory_list_lot_balances_v1(bigint,bigint,bigint,bigint,bigint,integer),
 core10.inventory_fefo_v1(bigint,bigint,bigint,numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core10.inventory_create_lot_command_v1(bigint,text,bigint,bigint,bigint,numeric,bigint,text,text),
 core10.inventory_lot_hold_v1(bigint,text,text,text), core10.inventory_lot_link_v1(bigint,bigint,text),
 core10.inventory_lot_start_recall_v1(bigint,text,text,text), core10.inventory_lot_close_recall_v1(bigint,text,text),
 core10.inventory_lot_recall_v1(bigint), core10.inventory_list_lot_balances_v1(bigint,bigint,bigint,bigint,bigint,integer),
 core10.inventory_fefo_v1(bigint,bigint,bigint,numeric) TO authenticated;

INSERT INTO core10.control_rpc_map_v1(rpc_name,status,feature_key,reason,lane,board_row,test_ref) VALUES
 ('inventory_create_lot_command_v1','enforced','inventory.lot_control','Lot stock command: create_inventory_command_v1 checks (stock master switch, kind feature) plus the lot-control feature on every touched site','Claude','B-012','tests/migrations/np03a-lots-e2e.sql'),
 ('inventory_lot_hold_v1','enforced','inventory.lot_control','Lot hold / release checks the lot-control feature, reason and separate-releaser params; managers only','Claude','B-012','tests/migrations/np03a-lots-e2e.sql'),
 ('inventory_lot_link_v1','enforced','inventory.lot_recall','Lot genealogy link checks the lot-recall feature; no cycles, no recalled lineage','Claude','B-012','tests/migrations/np03a-lots-e2e.sql'),
 ('inventory_lot_start_recall_v1','enforced','inventory.lot_recall','Recall start checks the lot-recall feature and genealogy param; blocks the lot and its descendants','Claude','B-012','tests/migrations/np03a-lots-e2e.sql'),
 ('inventory_lot_close_recall_v1','enforced','inventory.lot_recall','Recall close checks the lot-recall feature and the zero-stock param','Claude','B-012','tests/migrations/np03a-lots-e2e.sql');
