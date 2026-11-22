-- NP03A / B-012 (0207): GRN cancel before posting, return to supplier after posting, lot expiry read
-- (Claude Agent G, block 0200-0299). Builds on 0203 (PO -> GRN -> QC -> stock) and 0206 (PO approval).
-- Reuse first: the 0203 request ledger (_proc_replay_v1 / _proc_record_v1: per-key advisory lock, canonical audit
-- source 'procurement'), the A058 lot model already ported as inventory_lots_v1 (no lot balances, no second book),
-- Owner Control (control_check_v1, DEC-08 registry), the one stock ledger (post_stock_event only).
--  a) procurement_cancel_grn_v1: a received / inspected GRN (never a posted one) becomes 'cancelled'; its received
--     quantity stops reserving open PO quantity (_proc_open_qty_v1 ignores cancelled receipts); a cancelled receipt
--     no longer blocks PO short-close, and a PO whose receipts are all cancelled may still be cancelled.
--  b) supplier return: draft (procurement_save_return_v1) -> posted / cancelled (procurement_advance_return_v1)
--     against ONE posted GRN; qty <= accepted - already returned (drafts reserve), stock must be available; posting
--     writes a NEGATIVE stock event at the GRN location (core10.post_stock_event) and raises returned_qty on the GRN
--     line and the PO line. Owner Control feature procurement.supplier_return (reason_required, separate_approver,
--     max_return_qty); posting also needs the inventory.stock_event master switch. A return does not reopen PO
--     quantity (a replacement is a new PO / receipt).
--  c) procurement_list_lots_v1: STABLE scoped read of a business's lots with received / returned totals and days to
--     expiry, filter "expiring within N days", keyset pages <= 200; site-only staff see totals of readable sites only.
--  d) NOT done here: the 0206 approval payload unit stays 'currency_total'. No business or PO currency exists in
--     core10 (only price lists 0150 and finance accounts 0400 carry one), so no real currency code can be chosen
--     server-side without inventing it. Documented in docs/development/CLAUDE_BUILDER_B_HANDOFF.md (Agent G).
DO $dep$ BEGIN
 IF to_regclass('core10.goods_receipts_v1') IS NULL OR to_regclass('core10.purchase_orders_v1') IS NULL
 OR to_regprocedure('core10._proc_po_approval_gate_v1(bigint,integer)') IS NULL
 OR to_regprocedure('core10.post_stock_event(bigint,bigint,numeric,text)') IS NULL
 OR to_regprocedure('core10.owner_business_sites_v1(bigint,text,bigint,integer)') IS NULL
 THEN RAISE EXCEPTION 'PROC_0207_DEPENDENCY_NOT_CONNECTED'; END IF;
END $dep$;

INSERT INTO core10.control_catalog_v1
 (feature_key,title_en,title_bn,pack,default_enabled,default_stages,max_stages,allow_site_scope,approval_domain,approval_action,params) VALUES
 ('procurement.supplier_return','Return goods to the supplier after a receipt is posted','গ্রহণ পোস্ট হওয়ার পর সরবরাহকারীকে মাল ফেরত','NP03A',true,0,0,true,NULL,NULL,
  '{"reason_required":{"type":"bool","default":true,"label_en":"Reason required","label_bn":"কারণ লেখা বাধ্যতামূলক"},
    "separate_approver":{"type":"bool","default":true,"label_en":"Poster must differ from preparer","label_bn":"পোস্টকারী ও প্রস্তুতকারী আলাদা হবেন"},
    "max_return_qty":{"type":"numeric","min":0.001,"max":1000000,"default":100000,"label_en":"Maximum quantity per return line","label_bn":"প্রতি ফেরত লাইনে সর্বোচ্চ পরিমাণ"}}');

-- ---------- a) GRN cancel: status, who/when/why ----------
ALTER TABLE core10.goods_receipts_v1
 ADD COLUMN cancelled_by uuid, ADD COLUMN cancelled_at timestamptz,
 ADD COLUMN cancel_reason text CHECK (cancel_reason IS NULL OR length(btrim(cancel_reason)) BETWEEN 3 AND 300);
ALTER TABLE core10.goods_receipts_v1 DROP CONSTRAINT goods_receipts_v1_status_check;
ALTER TABLE core10.goods_receipts_v1 ADD CONSTRAINT goods_receipts_v1_status_check
 CHECK (status IN ('received','inspected','posted','cancelled'));
ALTER TABLE core10.goods_receipts_v1 DROP CONSTRAINT goods_receipts_v1_check;
ALTER TABLE core10.goods_receipts_v1 ADD CONSTRAINT goods_receipts_v1_check
 CHECK ((status='received' AND inspected_by IS NULL AND posted_by IS NULL)
     OR (status='inspected' AND inspected_by IS NOT NULL AND posted_by IS NULL)
     OR (status='posted' AND inspected_by IS NOT NULL AND posted_by IS NOT NULL)
     OR (status='cancelled' AND posted_by IS NULL));
ALTER TABLE core10.goods_receipts_v1 ADD CONSTRAINT goods_receipts_v1_cancel_v1
 CHECK ((status='cancelled') = (cancelled_by IS NOT NULL) AND (cancelled_by IS NULL) = (cancelled_at IS NULL)
    AND (cancelled_by IS NULL) = (cancel_reason IS NULL));

-- ---------- b) returned quantities on the receipt line and the PO line ----------
ALTER TABLE core10.goods_receipt_lines_v1 ADD COLUMN returned_qty numeric(15,3) NOT NULL DEFAULT 0;
ALTER TABLE core10.goods_receipt_lines_v1 ADD CONSTRAINT goods_receipt_lines_v1_returned_v1
 CHECK (returned_qty>=0 AND returned_qty=round(returned_qty,3) AND returned_qty<=coalesce(accepted_qty,0));
ALTER TABLE core10.purchase_order_lines_v1 ADD COLUMN returned_qty numeric(15,3) NOT NULL DEFAULT 0;
ALTER TABLE core10.purchase_order_lines_v1 ADD CONSTRAINT purchase_order_lines_v1_returned_v1
 CHECK (returned_qty>=0 AND returned_qty<=accepted_qty);

ALTER TABLE core10.procurement_requests_v1 DROP CONSTRAINT procurement_requests_v1_action_check;
ALTER TABLE core10.procurement_requests_v1 ADD CONSTRAINT procurement_requests_v1_action_check
 CHECK (action IN ('po_save','po_approve','po_cancel','po_close','grn_receive','grn_inspect','grn_post',
  'grn_cancel','return_save','return_post','return_cancel'));

CREATE TABLE core10.supplier_returns_v1 (
 id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, po_id bigint NOT NULL, grn_id bigint NOT NULL,
 site_id bigint NOT NULL, location_id bigint NOT NULL, supplier_id bigint NOT NULL,
 status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','posted','cancelled')),
 reason text CHECK (reason IS NULL OR length(btrim(reason)) BETWEEN 3 AND 300),
 version integer NOT NULL DEFAULT 1 CHECK (version>0),
 request_key text NOT NULL CHECK (request_key ~ '^[A-Za-z0-9_-]{8,100}$'),
 created_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 posted_by uuid, posted_at timestamptz, cancelled_by uuid, cancelled_at timestamptz,
 UNIQUE (business_id, request_key), UNIQUE (id, tenant_id, business_id, grn_id),
 FOREIGN KEY (grn_id, tenant_id, business_id) REFERENCES core10.goods_receipts_v1(id, tenant_id, business_id),
 FOREIGN KEY (po_id, tenant_id, business_id) REFERENCES core10.purchase_orders_v1(id, tenant_id, business_id),
 FOREIGN KEY (location_id, tenant_id, business_id, site_id) REFERENCES core10.stock_locations(id, tenant_id, business_id, site_id),
 FOREIGN KEY (supplier_id, tenant_id, business_id) REFERENCES core10.master_parties_v1(id, tenant_id, business_id),
 CHECK ((posted_by IS NULL) = (posted_at IS NULL) AND (cancelled_by IS NULL) = (cancelled_at IS NULL)),
 CHECK ((status='draft' AND posted_by IS NULL AND cancelled_by IS NULL)
     OR (status='posted' AND posted_by IS NOT NULL AND cancelled_by IS NULL)
     OR (status='cancelled' AND posted_by IS NULL AND cancelled_by IS NOT NULL))
);
CREATE INDEX supplier_returns_grn_ix ON core10.supplier_returns_v1 (grn_id);
CREATE INDEX supplier_returns_business_ix ON core10.supplier_returns_v1 (business_id, id DESC);

CREATE TABLE core10.supplier_return_lines_v1 (
 return_id bigint NOT NULL, tenant_id bigint NOT NULL, business_id bigint NOT NULL, grn_id bigint NOT NULL,
 line_no integer NOT NULL, item_id bigint NOT NULL, lot_id bigint,
 quantity numeric(15,3) NOT NULL CHECK (quantity>0 AND quantity<=1000000 AND quantity=round(quantity,3)),
 stock_movement_id bigint,
 PRIMARY KEY (return_id, line_no),
 FOREIGN KEY (return_id, tenant_id, business_id, grn_id) REFERENCES core10.supplier_returns_v1(id, tenant_id, business_id, grn_id),
 FOREIGN KEY (grn_id, line_no) REFERENCES core10.goods_receipt_lines_v1(grn_id, line_no),
 FOREIGN KEY (item_id, tenant_id, business_id) REFERENCES core10.items(id, tenant_id, business_id),
 FOREIGN KEY (lot_id, tenant_id, business_id) REFERENCES core10.inventory_lots_v1(id, tenant_id, business_id),
 FOREIGN KEY (stock_movement_id) REFERENCES core10.stock_movements(id)
);
CREATE INDEX supplier_return_lines_grn_ix ON core10.supplier_return_lines_v1 (grn_id, line_no);

-- c) lot expiry read support (A058 quality_lots_expiry_v1 idea, on the canonical lot master).
CREATE INDEX inventory_lots_business_expiry_ix ON core10.inventory_lots_v1 (business_id, expires_on, id);
CREATE INDEX goods_receipt_lines_lot_ix ON core10.goods_receipt_lines_v1 (lot_id) WHERE lot_id IS NOT NULL;

ALTER TABLE core10.supplier_returns_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE core10.supplier_return_lines_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON core10.supplier_returns_v1, core10.supplier_return_lines_v1 FROM PUBLIC, authenticated;

-- ---------- helpers ----------
CREATE FUNCTION core10._proc_return_json_v1(p_return bigint) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
 SELECT jsonb_build_object('return_id',r.id,'grn_id',r.grn_id,'po_id',r.po_id,'business_id',r.business_id,
  'site_id',r.site_id,'location_id',r.location_id,'supplier_id',r.supplier_id,'status',r.status,'version',r.version,
  'reason',r.reason,'created_by',r.created_by,'created_at',r.created_at,'posted_by',r.posted_by,'posted_at',r.posted_at,
  'cancelled_by',r.cancelled_by,'cancelled_at',r.cancelled_at,
  'lines',coalesce((SELECT jsonb_agg(jsonb_build_object('line_no',l.line_no,'item_id',l.item_id,'lot_id',l.lot_id,
    'quantity',l.quantity,'stock_movement_id',l.stock_movement_id) ORDER BY l.line_no)
    FROM core10.supplier_return_lines_v1 l WHERE l.return_id=r.id),'[]'::jsonb))
 FROM core10.supplier_returns_v1 r WHERE r.id=p_return
$$;

-- 0203 shape + cancel fields, returned_qty per line and the receipt's supplier returns.
CREATE OR REPLACE FUNCTION core10._proc_grn_json_v1(p_grn bigint) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
 SELECT jsonb_build_object('grn_id',g.id,'po_id',g.po_id,'business_id',g.business_id,'site_id',g.site_id,
  'location_id',g.location_id,'supplier_ref',g.supplier_ref,'status',g.status,'version',g.version,
  'received_by',g.received_by,'received_at',g.received_at,'inspected_by',g.inspected_by,'posted_by',g.posted_by,
  'posted_at',g.posted_at,'cancelled_by',g.cancelled_by,'cancelled_at',g.cancelled_at,'cancel_reason',g.cancel_reason,
  'lines',coalesce((SELECT jsonb_agg(jsonb_build_object('line_no',l.line_no,'item_id',l.item_id,
   'received_qty',l.received_qty,'accepted_qty',l.accepted_qty,
   'rejected_qty',CASE WHEN l.accepted_qty IS NULL THEN NULL ELSE l.received_qty-l.accepted_qty END,
   'returned_qty',l.returned_qty,
   'qc_notes',l.qc_notes,'lot_code',l.lot_code,'manufactured_on',l.manufactured_on,'expires_on',l.expires_on,
   'lot_id',l.lot_id,'stock_movement_id',l.stock_movement_id) ORDER BY l.line_no)
   FROM core10.goods_receipt_lines_v1 l WHERE l.grn_id=g.id),'[]'::jsonb),
  'returns',coalesce((SELECT jsonb_agg(core10._proc_return_json_v1(r.id) ORDER BY r.id)
   FROM core10.supplier_returns_v1 r WHERE r.grn_id=g.id),'[]'::jsonb))
 FROM core10.goods_receipts_v1 g WHERE g.id=p_grn
$$;

-- 0203 shape + returned_qty per line.
CREATE OR REPLACE FUNCTION core10._proc_po_json_v1(p_po bigint) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
 SELECT jsonb_build_object('po_id',p.id,'business_id',p.business_id,'site_id',p.site_id,'supplier_id',p.supplier_id,
  'supplier_name_en',s.name_en,'supplier_name_bn',s.name_bn,'status',p.status,'version',p.version,
  'expected_on',p.expected_on,'note',p.note,'total_amount',p.total_amount,'created_by',p.created_by,
  'created_at',p.created_at,'approved_by',p.approved_by,
  'lines',coalesce((SELECT jsonb_agg(jsonb_build_object('line_no',l.line_no,'item_id',l.item_id,'sku',i.sku,
    'name_en',i.name_en,'name_bn',i.name_bn,'quantity',l.quantity,'unit_price',l.unit_price,
    'amount',round(l.quantity*l.unit_price,2),'accepted_qty',l.accepted_qty,'rejected_qty',l.rejected_qty,
    'returned_qty',l.returned_qty) ORDER BY l.line_no)
    FROM core10.purchase_order_lines_v1 l JOIN core10.items i ON i.id=l.item_id WHERE l.po_id=p.id),'[]'::jsonb))
 FROM core10.purchase_orders_v1 p JOIN core10.master_parties_v1 s ON s.id=p.supplier_id WHERE p.id=p_po
$$;

-- Quantity still open on a PO line: ordered minus accepted on posted receipts minus received on unposted ones;
-- a cancelled receipt reserves nothing.
CREATE OR REPLACE FUNCTION core10._proc_open_qty_v1(p_po bigint, p_line integer) RETURNS numeric
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
 SELECT l.quantity - coalesce((SELECT sum(CASE WHEN g.status='posted' THEN gl.accepted_qty ELSE gl.received_qty END)
   FROM core10.goods_receipt_lines_v1 gl JOIN core10.goods_receipts_v1 g ON g.id=gl.grn_id
   WHERE gl.po_id=p_po AND gl.line_no=p_line AND g.status<>'cancelled'),0)
 FROM core10.purchase_order_lines_v1 l WHERE l.po_id=p_po AND l.line_no=p_line
$$;

-- approve / cancel / close. Same as 0206 (with its post-lock Auth re-check) except that a cancelled receipt
-- neither blocks cancelling the PO nor short-closing it.
CREATE OR REPLACE FUNCTION core10.procurement_advance_po_v1(p_po bigint, p_action text, p_version integer, p_key text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_actor uuid := core10.actor_uid(); p core10.purchase_orders_v1%ROWTYPE; c jsonb; v_sha text; v_id bigint;
 v_appr jsonb := '{}';
BEGIN
 IF v_actor IS NULL OR p_action IS NULL OR p_action NOT IN ('approve','cancel','close') OR p_version IS NULL THEN RAISE EXCEPTION 'PROC_INVALID_ACTION'; END IF;
 SELECT * INTO p FROM core10.purchase_orders_v1 WHERE id=p_po;
 IF NOT FOUND OR NOT core10.can_see_business(p.tenant_id,p.business_id) THEN RAISE EXCEPTION 'PROC_SCOPE'; END IF;
 IF NOT core10.can_manage(p.tenant_id,p.business_id) AND NOT (p_action='cancel' AND p.created_by=v_actor)
 THEN RAISE EXCEPTION 'PROC_PERMISSION_DENIED'; END IF;
 SELECT * INTO p FROM core10.purchase_orders_v1 WHERE id=p_po FOR UPDATE;
 -- Re-read Auth after the row lock; permission could have been revoked while waiting.
 IF NOT core10.can_see_business(p.tenant_id,p.business_id) THEN RAISE EXCEPTION 'PROC_SCOPE'; END IF;
 IF NOT core10.can_manage(p.tenant_id,p.business_id) AND NOT (p_action='cancel' AND p.created_by=v_actor)
 THEN RAISE EXCEPTION 'PROC_PERMISSION_DENIED'; END IF;
 c := core10.control_check_v1(p.business_id, 'procurement.purchase_order', p.site_id);
 v_sha := core10._proc_sha_v1(jsonb_build_object('po',p_po,'a',p_action,'v',p_version));
 v_id := core10._proc_replay_v1(p.business_id,p_key,'po_'||p_action,v_sha);
 IF v_id IS NOT NULL THEN RETURN core10._proc_po_json_v1(v_id) || '{"replayed":true}'; END IF;
 IF p.version<>p_version THEN RAISE EXCEPTION 'PROC_STALE_VERSION:%', p.version; END IF;
 IF p_action='approve' THEN
  IF p.status<>'draft' THEN RAISE EXCEPTION 'PROC_INVALID_TRANSITION'; END IF;
  IF (c->'params'->>'separate_approver')::boolean AND p.created_by=v_actor THEN RAISE EXCEPTION 'PROC_SAME_ACTOR'; END IF;
  -- Approval port: never self-approve or fabricate a receipt; stages = 0 returns '{}' (0203 behaviour).
  v_appr := core10._proc_po_approval_gate_v1(p.id, (c->>'stages')::int);
  UPDATE core10.purchase_orders_v1 SET status='approved',approved_by=v_actor,approved_at=now(),version=version+1 WHERE id=p.id;
 ELSIF p_action='cancel' THEN
  IF p.status NOT IN ('draft','approved') OR EXISTS(SELECT 1 FROM core10.goods_receipts_v1 WHERE po_id=p.id AND status<>'cancelled')
  THEN RAISE EXCEPTION 'PROC_INVALID_TRANSITION'; END IF;
  UPDATE core10.purchase_orders_v1 SET status='cancelled',closed_by=v_actor,closed_at=now(),version=version+1 WHERE id=p.id;
 ELSE
  IF p.status NOT IN ('approved','partially_received')
   OR EXISTS(SELECT 1 FROM core10.goods_receipts_v1 WHERE po_id=p.id AND status NOT IN ('posted','cancelled'))
  THEN RAISE EXCEPTION 'PROC_INVALID_TRANSITION'; END IF;
  UPDATE core10.purchase_orders_v1 SET status='closed',closed_by=v_actor,closed_at=now(),version=version+1 WHERE id=p.id;
 END IF;
 PERFORM core10._proc_record_v1(p.tenant_id,p.business_id,p_key,'po_'||p_action,p.id,v_sha,'po:'||p.id||':'||p_action,
  jsonb_build_object('po_id',p.id,'from_version',p_version) || v_appr);
 RETURN core10._proc_po_json_v1(p.id) || jsonb_build_object('replayed',false) || v_appr;
END $$;

-- 0204 drill-down: "receipts waiting" counts receipts still waiting for QC / posting, never cancelled ones.
CREATE OR REPLACE FUNCTION core10.owner_business_sites_v1(p_business bigint, p_kind text DEFAULT NULL, p_after_site bigint DEFAULT NULL,
 p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint; v_limit int := least(greatest(coalesce(p_limit,50),1),200); v_rows jsonb;
BEGIN
 SELECT tenant_id INTO t FROM core10.businesses WHERE id=p_business;
 IF core10.actor_uid() IS NULL OR t IS NULL OR NOT core10.can_business(t,p_business) THEN RAISE EXCEPTION 'DASH_SCOPE'; END IF;
 IF p_kind IS NOT NULL AND p_kind NOT IN ('showroom','factory','godown','warehouse','project') THEN RAISE EXCEPTION 'DASH_INVALID_FILTER'; END IF;
 WITH s AS (SELECT id, kind, label FROM core10.sites
   WHERE business_id=p_business AND (p_kind IS NULL OR kind=p_kind) AND (p_after_site IS NULL OR id>p_after_site)
     AND core10.can_site(t,p_business,id,'stock.read') ORDER BY id LIMIT v_limit),
 bal AS (SELECT site_id, count(*) FILTER (WHERE on_hand>0) AS stock_rows, coalesce(sum(on_hand),0) AS units
   FROM core10.stock_balances_v1 WHERE business_id=p_business AND site_id IN (SELECT id FROM s) GROUP BY 1),
 loc AS (SELECT site_id, count(*) AS locations FROM core10.stock_locations WHERE business_id=p_business AND site_id IN (SELECT id FROM s) GROUP BY 1),
 po AS (SELECT site_id, count(*) AS open_pos FROM core10.purchase_orders_v1
   WHERE business_id=p_business AND site_id IN (SELECT id FROM s) AND status IN ('approved','partially_received') GROUP BY 1),
 gr AS (SELECT site_id, count(*) AS receipts_waiting FROM core10.goods_receipts_v1
   WHERE business_id=p_business AND site_id IN (SELECT id FROM s) AND status IN ('received','inspected') GROUP BY 1),
 cm AS (SELECT x.site_id, count(DISTINCT x.id) AS commands_open FROM (
   SELECT id, source_site_id AS site_id FROM core10.inventory_commands_v1 WHERE business_id=p_business AND status IN ('draft','confirmed')
   UNION ALL SELECT id, destination_site_id FROM core10.inventory_commands_v1 WHERE business_id=p_business AND status IN ('draft','confirmed')) x
   WHERE x.site_id IN (SELECT id FROM s) GROUP BY 1)
 SELECT coalesce(jsonb_agg(jsonb_build_object('site_id',s.id,'kind',s.kind,'label',s.label,'locations',coalesce(loc.locations,0),
   'stock_rows',coalesce(bal.stock_rows,0),'units',coalesce(bal.units,0),'open_pos',coalesce(po.open_pos,0),
   'receipts_waiting',coalesce(gr.receipts_waiting,0),'commands_open',coalesce(cm.commands_open,0)) ORDER BY s.id),'[]'::jsonb)
 INTO v_rows FROM s LEFT JOIN bal ON bal.site_id=s.id LEFT JOIN loc ON loc.site_id=s.id LEFT JOIN po ON po.site_id=s.id
  LEFT JOIN gr ON gr.site_id=s.id LEFT JOIN cm ON cm.site_id=s.id;
 RETURN jsonb_build_object('business_id',p_business,'kind',p_kind,'items',v_rows,'limit',v_limit,
  'next_after_site',CASE WHEN jsonb_array_length(v_rows)=v_limit THEN (v_rows->(v_limit-1)->>'site_id')::bigint END);
END $$;

-- ---------- a) cancel a GRN before posting ----------
-- The receiver or a manager with stock.post at the receipt location; reason 3-300 characters.
CREATE FUNCTION core10.procurement_cancel_grn_v1(p_grn bigint, p_version integer, p_reason text, p_key text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_actor uuid := core10.actor_uid(); g core10.goods_receipts_v1%ROWTYPE; v_sha text; v_id bigint;
BEGIN
 IF v_actor IS NULL OR p_version IS NULL THEN RAISE EXCEPTION 'PROC_INVALID_ACTION'; END IF;
 -- Authorize before locking an untrusted row; re-check after the locks.
 SELECT * INTO g FROM core10.goods_receipts_v1 WHERE id=p_grn;
 IF NOT FOUND OR NOT core10.can_see_business(g.tenant_id,g.business_id) THEN RAISE EXCEPTION 'PROC_SCOPE'; END IF;
 IF NOT core10.inventory_action_authorized_v1(g.tenant_id,g.business_id,g.location_id,'stock.post')
  OR NOT (g.received_by=v_actor OR core10.can_manage(g.tenant_id,g.business_id)) THEN RAISE EXCEPTION 'PROC_PERMISSION_DENIED'; END IF;
 -- Same lock order as receive / post (PO, then GRN): the freed quantity is visible to the next receipt at once.
 PERFORM 1 FROM core10.purchase_orders_v1 WHERE id=g.po_id FOR UPDATE;
 SELECT * INTO g FROM core10.goods_receipts_v1 WHERE id=p_grn FOR UPDATE;
 IF NOT core10.can_see_business(g.tenant_id,g.business_id) THEN RAISE EXCEPTION 'PROC_SCOPE'; END IF;
 IF NOT core10.inventory_action_authorized_v1(g.tenant_id,g.business_id,g.location_id,'stock.post')
  OR NOT (g.received_by=v_actor OR core10.can_manage(g.tenant_id,g.business_id)) THEN RAISE EXCEPTION 'PROC_PERMISSION_DENIED'; END IF;
 PERFORM core10.control_check_v1(g.business_id, 'procurement.goods_receipt', g.site_id);
 v_sha := core10._proc_sha_v1(jsonb_build_object('g',p_grn,'v',p_version,'r',p_reason));
 v_id := core10._proc_replay_v1(g.business_id,p_key,'grn_cancel',v_sha);
 IF v_id IS NOT NULL THEN RETURN core10._proc_grn_json_v1(v_id) || '{"replayed":true}'; END IF;
 IF g.version<>p_version THEN RAISE EXCEPTION 'PROC_STALE_VERSION:%', g.version; END IF;
 IF g.status NOT IN ('received','inspected') THEN RAISE EXCEPTION 'PROC_INVALID_TRANSITION'; END IF;
 IF p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 3 AND 300 THEN RAISE EXCEPTION 'PROC_CANCEL_REASON_REQUIRED'; END IF;
 UPDATE core10.goods_receipts_v1 SET status='cancelled',cancelled_by=v_actor,cancelled_at=now(),cancel_reason=btrim(p_reason),
  version=version+1 WHERE id=g.id;
 PERFORM core10._proc_record_v1(g.tenant_id,g.business_id,p_key,'grn_cancel',g.id,v_sha,'grn:'||g.id||':cancelled',
  jsonb_build_object('grn_id',g.id,'po_id',g.po_id,'from_status',g.status,'from_version',p_version,
   'freed',(SELECT jsonb_agg(jsonb_build_object('line_no',line_no,'quantity',received_qty) ORDER BY line_no)
     FROM core10.goods_receipt_lines_v1 WHERE grn_id=g.id)));
 RETURN core10._proc_grn_json_v1(g.id) || '{"replayed":false}';
END $$;

-- ---------- b) supplier return ----------
-- Draft a return against one posted GRN. p_lines: [{"line_no":1,"quantity":..}, ...]
CREATE FUNCTION core10.procurement_save_return_v1(p_grn bigint, p_lines jsonb, p_reason text, p_key text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_actor uuid := core10.actor_uid(); g core10.goods_receipts_v1%ROWTYPE; c jsonb; v_sha text; v_id bigint;
 e jsonb; v_line int; v_qty numeric; gl core10.goods_receipt_lines_v1%ROWTYPE; v_reserved numeric; v_on_hand numeric;
 v_supplier bigint;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'PROC_SCOPE'; END IF;
 SELECT * INTO g FROM core10.goods_receipts_v1 WHERE id=p_grn;
 IF NOT FOUND OR NOT core10.can_see_business(g.tenant_id,g.business_id) THEN RAISE EXCEPTION 'PROC_SCOPE'; END IF;
 IF NOT core10.inventory_action_authorized_v1(g.tenant_id,g.business_id,g.location_id,'stock.post') THEN RAISE EXCEPTION 'PROC_PERMISSION_DENIED'; END IF;
 -- The GRN row lock serializes every return drafted or posted against this receipt.
 SELECT * INTO g FROM core10.goods_receipts_v1 WHERE id=p_grn FOR UPDATE;
 IF NOT core10.can_see_business(g.tenant_id,g.business_id) THEN RAISE EXCEPTION 'PROC_SCOPE'; END IF;
 IF NOT core10.inventory_action_authorized_v1(g.tenant_id,g.business_id,g.location_id,'stock.post') THEN RAISE EXCEPTION 'PROC_PERMISSION_DENIED'; END IF;
 c := core10.control_check_v1(g.business_id, 'procurement.supplier_return', g.site_id);
 v_sha := core10._proc_sha_v1(jsonb_build_object('g',p_grn,'x',p_lines,'r',p_reason));
 v_id := core10._proc_replay_v1(g.business_id,p_key,'return_save',v_sha);
 IF v_id IS NOT NULL THEN RETURN core10._proc_return_json_v1(v_id) || '{"replayed":true}'; END IF;
 IF g.status<>'posted' THEN RAISE EXCEPTION 'PROC_GRN_NOT_POSTED'; END IF;
 IF nullif(btrim(p_reason),'') IS NOT NULL AND length(btrim(p_reason)) NOT BETWEEN 3 AND 300 THEN RAISE EXCEPTION 'PROC_RETURN_REASON_INVALID'; END IF;
 IF (c->'params'->>'reason_required')::boolean AND nullif(btrim(p_reason),'') IS NULL THEN RAISE EXCEPTION 'PROC_RETURN_REASON_REQUIRED'; END IF;
 IF p_lines IS NULL OR jsonb_typeof(p_lines)<>'array' OR jsonb_array_length(p_lines) NOT BETWEEN 1 AND 200
  OR (SELECT count(DISTINCT x->>'line_no') FROM jsonb_array_elements(p_lines) x)<>jsonb_array_length(p_lines)
 THEN RAISE EXCEPTION 'PROC_LINES_INVALID'; END IF;
 SELECT supplier_id INTO v_supplier FROM core10.purchase_orders_v1 WHERE id=g.po_id;
 INSERT INTO core10.supplier_returns_v1(tenant_id,business_id,po_id,grn_id,site_id,location_id,supplier_id,reason,request_key,created_by)
 VALUES (g.tenant_id,g.business_id,g.po_id,g.id,g.site_id,g.location_id,v_supplier,nullif(btrim(p_reason),''),p_key,v_actor)
 RETURNING id INTO v_id;
 FOR e IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
  IF jsonb_typeof(e)<>'object' OR jsonb_typeof(e->'line_no')<>'number' OR jsonb_typeof(e->'quantity')<>'number'
  THEN RAISE EXCEPTION 'PROC_LINES_INVALID'; END IF;
  v_line := (e->>'line_no')::int; v_qty := (e->>'quantity')::numeric;
  SELECT * INTO gl FROM core10.goods_receipt_lines_v1 WHERE grn_id=g.id AND line_no=v_line;
  IF NOT FOUND OR v_qty<=0 OR v_qty<>round(v_qty,3) THEN RAISE EXCEPTION 'PROC_LINES_INVALID'; END IF;
  IF v_qty > (c->'params'->>'max_return_qty')::numeric THEN RAISE EXCEPTION 'CONTROL_LIMIT:max_return_qty'; END IF;
  -- Open drafts reserve their quantity so two drafts can never together exceed what was accepted.
  SELECT coalesce(sum(rl.quantity),0) INTO v_reserved FROM core10.supplier_return_lines_v1 rl
   JOIN core10.supplier_returns_v1 r ON r.id=rl.return_id
   WHERE rl.grn_id=g.id AND rl.line_no=v_line AND r.status='draft' AND r.id<>v_id;
  IF v_qty > coalesce(gl.accepted_qty,0) - gl.returned_qty - v_reserved THEN RAISE EXCEPTION 'PROC_RETURN_EXCEEDS_ACCEPTED'; END IF;
  SELECT on_hand INTO v_on_hand FROM core10.stock_balances_v1 WHERE location_id=g.location_id AND item_id=gl.item_id;
  IF coalesce(v_on_hand,0) < v_qty THEN RAISE EXCEPTION 'PROC_INSUFFICIENT_STOCK'; END IF;
  INSERT INTO core10.supplier_return_lines_v1(return_id,tenant_id,business_id,grn_id,line_no,item_id,lot_id,quantity)
  VALUES (v_id,g.tenant_id,g.business_id,g.id,v_line,gl.item_id,gl.lot_id,v_qty);
 END LOOP;
 PERFORM core10._proc_record_v1(g.tenant_id,g.business_id,p_key,'return_save',v_id,v_sha,'return:'||v_id||':draft',
  jsonb_build_object('return_id',v_id,'grn_id',g.id,'po_id',g.po_id,'lines',jsonb_array_length(p_lines),
   'quantity',(SELECT sum(quantity) FROM core10.supplier_return_lines_v1 WHERE return_id=v_id)));
 RETURN core10._proc_return_json_v1(v_id) || '{"replayed":false}';
END $$;

-- post (draft -> posted: negative stock event at the GRN location, returned_qty on GRN and PO lines)
-- cancel (draft -> cancelled: frees the reserved quantity; nothing moves).
CREATE FUNCTION core10.procurement_advance_return_v1(p_return bigint, p_action text, p_version integer, p_key text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_actor uuid := core10.actor_uid(); r core10.supplier_returns_v1%ROWTYPE; c jsonb; v_sha text; v_id bigint;
 l record; v_mv bigint;
BEGIN
 IF v_actor IS NULL OR p_action IS NULL OR p_action NOT IN ('post','cancel') OR p_version IS NULL THEN RAISE EXCEPTION 'PROC_INVALID_ACTION'; END IF;
 SELECT * INTO r FROM core10.supplier_returns_v1 WHERE id=p_return;
 IF NOT FOUND OR NOT core10.can_see_business(r.tenant_id,r.business_id) THEN RAISE EXCEPTION 'PROC_SCOPE'; END IF;
 IF NOT core10.inventory_action_authorized_v1(r.tenant_id,r.business_id,r.location_id,'stock.post')
  OR (p_action='cancel' AND r.created_by<>v_actor AND NOT core10.can_manage(r.tenant_id,r.business_id))
 THEN RAISE EXCEPTION 'PROC_PERMISSION_DENIED'; END IF;
 -- Lock order PO -> GRN -> return, the same as GRN posting.
 PERFORM 1 FROM core10.purchase_orders_v1 WHERE id=r.po_id FOR UPDATE;
 PERFORM 1 FROM core10.goods_receipts_v1 WHERE id=r.grn_id FOR UPDATE;
 SELECT * INTO r FROM core10.supplier_returns_v1 WHERE id=p_return FOR UPDATE;
 IF NOT core10.can_see_business(r.tenant_id,r.business_id) THEN RAISE EXCEPTION 'PROC_SCOPE'; END IF;
 IF NOT core10.inventory_action_authorized_v1(r.tenant_id,r.business_id,r.location_id,'stock.post')
  OR (p_action='cancel' AND r.created_by<>v_actor AND NOT core10.can_manage(r.tenant_id,r.business_id))
 THEN RAISE EXCEPTION 'PROC_PERMISSION_DENIED'; END IF;
 c := core10.control_check_v1(r.business_id, 'procurement.supplier_return', r.site_id);
 IF p_action='post' THEN PERFORM core10.control_check_v1(r.business_id, 'inventory.stock_event', r.site_id); END IF;
 v_sha := core10._proc_sha_v1(jsonb_build_object('ret',p_return,'a',p_action,'v',p_version));
 v_id := core10._proc_replay_v1(r.business_id,p_key,'return_'||p_action,v_sha);
 IF v_id IS NOT NULL THEN RETURN core10._proc_return_json_v1(v_id) || '{"replayed":true}'; END IF;
 IF r.version<>p_version THEN RAISE EXCEPTION 'PROC_STALE_VERSION:%', r.version; END IF;
 IF r.status<>'draft' THEN RAISE EXCEPTION 'PROC_INVALID_TRANSITION'; END IF;
 IF p_action='post' THEN
  IF (c->'params'->>'separate_approver')::boolean AND r.created_by=v_actor THEN RAISE EXCEPTION 'PROC_SAME_ACTOR'; END IF;
  IF (c->'params'->>'reason_required')::boolean AND r.reason IS NULL THEN RAISE EXCEPTION 'PROC_RETURN_REASON_REQUIRED'; END IF;
  FOR l IN SELECT rl.*, gl.accepted_qty, gl.returned_qty FROM core10.supplier_return_lines_v1 rl
    JOIN core10.goods_receipt_lines_v1 gl ON gl.grn_id=rl.grn_id AND gl.line_no=rl.line_no
    WHERE rl.return_id=r.id ORDER BY rl.line_no LOOP
   IF l.quantity > (c->'params'->>'max_return_qty')::numeric THEN RAISE EXCEPTION 'CONTROL_LIMIT:max_return_qty'; END IF;
   IF l.quantity > coalesce(l.accepted_qty,0) - l.returned_qty THEN RAISE EXCEPTION 'PROC_RETURN_EXCEEDS_ACCEPTED'; END IF;
   BEGIN
    v_mv := core10.post_stock_event(r.location_id,l.item_id,-l.quantity,'c10-ret-'||r.id||'-'||l.line_no);
   EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='insufficient_stock' THEN RAISE EXCEPTION 'PROC_INSUFFICIENT_STOCK'; END IF;
    RAISE;
   END;
   UPDATE core10.supplier_return_lines_v1 SET stock_movement_id=v_mv WHERE return_id=r.id AND line_no=l.line_no;
   UPDATE core10.goods_receipt_lines_v1 SET returned_qty=returned_qty+l.quantity WHERE grn_id=r.grn_id AND line_no=l.line_no;
   UPDATE core10.purchase_order_lines_v1 SET returned_qty=returned_qty+l.quantity WHERE po_id=r.po_id AND line_no=l.line_no;
  END LOOP;
  UPDATE core10.supplier_returns_v1 SET status='posted',posted_by=v_actor,posted_at=now(),version=version+1 WHERE id=r.id;
 ELSE
  UPDATE core10.supplier_returns_v1 SET status='cancelled',cancelled_by=v_actor,cancelled_at=now(),version=version+1 WHERE id=r.id;
 END IF;
 PERFORM core10._proc_record_v1(r.tenant_id,r.business_id,p_key,'return_'||p_action,r.id,v_sha,'return:'||r.id||':'||p_action,
  jsonb_build_object('return_id',r.id,'grn_id',r.grn_id,'po_id',r.po_id,'from_version',p_version,
   'stock_movements',(SELECT jsonb_agg(stock_movement_id ORDER BY line_no) FROM core10.supplier_return_lines_v1
     WHERE return_id=r.id AND stock_movement_id IS NOT NULL)));
 RETURN core10._proc_return_json_v1(r.id) || '{"replayed":false}';
END $$;

-- ---------- c) lot expiry read (STABLE, scoped, keyset pages <= 200) ----------
-- Lots of one business ordered by expiry (no expiry last), with accepted and returned totals over POSTED receipts
-- at the sites the caller may read (stock.read; explicit site denies win, as in 0205). A lot with no readable
-- receipt is not listed. p_expiring_within_days = N lists lots whose expiry is on or before today + N (already
-- expired included). Cursor: next_after {expires_on ('infinity' for no expiry), lot_id}.
CREATE FUNCTION core10.procurement_list_lots_v1(p_business bigint, p_site bigint DEFAULT NULL,
 p_expiring_within_days integer DEFAULT NULL, p_after_expires_on date DEFAULT NULL, p_after_lot bigint DEFAULT NULL,
 p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint; v_limit int := least(greatest(coalesce(p_limit,50),1),200); v_rows jsonb;
 v_actor uuid := core10.actor_uid(); v_biz boolean; v_sites bigint[];
BEGIN
 SELECT tenant_id INTO t FROM core10.businesses WHERE id=p_business;
 IF v_actor IS NULL OR t IS NULL OR NOT core10.can_see_business(t,p_business) THEN RAISE EXCEPTION 'PROC_SCOPE'; END IF;
 IF p_site IS NOT NULL AND NOT core10.can_site(t,p_business,p_site,'stock.read') THEN RAISE EXCEPTION 'PROC_SCOPE'; END IF;
 IF (p_after_expires_on IS NULL) <> (p_after_lot IS NULL)
  OR (p_expiring_within_days IS NOT NULL AND p_expiring_within_days NOT BETWEEN 0 AND 3650) THEN RAISE EXCEPTION 'PROC_INVALID_FILTER'; END IF;
 v_biz := core10.can_business(t,p_business);
 SELECT coalesce(array_agg(s.id),'{}'::bigint[]) INTO v_sites FROM core10.sites s
  WHERE s.tenant_id=t AND s.business_id=p_business AND (p_site IS NULL OR s.id=p_site)
    AND CASE WHEN s.id IN (SELECT gr.site_id FROM core10.site_grants gr WHERE gr.user_id=v_actor)
             THEN core10.can_site(t,p_business,s.id,'stock.read')
             ELSE v_biz END;
 WITH agg AS (
  SELECT gl.lot_id, sum(coalesce(gl.accepted_qty,0)) AS received_qty, sum(gl.returned_qty) AS returned_qty,
   array_agg(DISTINCT g.site_id ORDER BY g.site_id) AS site_ids, min(g.posted_at) AS first_received_at
  FROM core10.goods_receipt_lines_v1 gl JOIN core10.goods_receipts_v1 g ON g.id=gl.grn_id
  WHERE gl.business_id=p_business AND gl.lot_id IS NOT NULL AND g.status='posted' AND g.site_id=ANY(v_sites)
  GROUP BY gl.lot_id),
 page AS (
  SELECT lt.*, a.received_qty, a.returned_qty, a.site_ids, a.first_received_at,
   coalesce(lt.expires_on,'infinity'::date) AS sort_exp
  FROM core10.inventory_lots_v1 lt JOIN agg a ON a.lot_id=lt.id
  WHERE lt.business_id=p_business AND lt.tenant_id=t
    AND (p_expiring_within_days IS NULL OR (lt.expires_on IS NOT NULL AND lt.expires_on<=current_date+p_expiring_within_days))
    AND (p_after_lot IS NULL OR (coalesce(lt.expires_on,'infinity'::date),lt.id)>(p_after_expires_on,p_after_lot))
  ORDER BY coalesce(lt.expires_on,'infinity'::date), lt.id LIMIT v_limit)
 SELECT coalesce(jsonb_agg(jsonb_build_object('lot_id',p.id,'item_id',p.item_id,'sku',i.sku,'name_en',i.name_en,'name_bn',i.name_bn,
   'lot_code',p.lot_code,'status',p.status,'manufactured_on',p.manufactured_on,'expires_on',p.expires_on,
   'days_to_expiry',CASE WHEN p.expires_on IS NOT NULL THEN p.expires_on-current_date END,
   'expired',coalesce(p.expires_on<current_date,false),
   'received_qty',p.received_qty,'returned_qty',p.returned_qty,'net_received_qty',p.received_qty-p.returned_qty,
   'site_ids',to_jsonb(p.site_ids),'first_received_at',p.first_received_at,'sort_expires_on',p.sort_exp)
   ORDER BY p.sort_exp, p.id),'[]'::jsonb)
 INTO v_rows FROM page p JOIN core10.items i ON i.id=p.item_id;
 RETURN jsonb_build_object('business_id',p_business,'site_id',p_site,'expiring_within_days',p_expiring_within_days,
  'as_of',current_date,'items',coalesce((SELECT jsonb_agg(a.x - 'sort_expires_on' ORDER BY a.o) FROM jsonb_array_elements(v_rows) WITH ORDINALITY a(x,o)),'[]'::jsonb),
  'limit',v_limit,'on_hand_by_lot','NOT_CONNECTED',
  'next_after',CASE WHEN jsonb_array_length(v_rows)=v_limit THEN jsonb_build_object(
   'expires_on',v_rows->(v_limit-1)->>'sort_expires_on','lot_id',(v_rows->(v_limit-1)->>'lot_id')::bigint) END);
END $$;

REVOKE ALL ON FUNCTION core10._proc_return_json_v1(bigint) FROM PUBLIC, authenticated;
REVOKE ALL ON FUNCTION core10.procurement_cancel_grn_v1(bigint,integer,text,text),
 core10.procurement_save_return_v1(bigint,jsonb,text,text), core10.procurement_advance_return_v1(bigint,text,integer,text),
 core10.procurement_list_lots_v1(bigint,bigint,integer,date,bigint,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core10.procurement_cancel_grn_v1(bigint,integer,text,text),
 core10.procurement_save_return_v1(bigint,jsonb,text,text), core10.procurement_advance_return_v1(bigint,text,integer,text),
 core10.procurement_list_lots_v1(bigint,bigint,integer,date,bigint,integer) TO authenticated;

INSERT INTO core10.control_rpc_map_v1(rpc_name,status,feature_key,reason,lane,board_row,test_ref) VALUES
 ('procurement_cancel_grn_v1','enforced','procurement.goods_receipt','GRN cancel (received/inspected only) checks the goods-receipt control; frees open PO quantity','Claude','B-012','tests/migrations/np03a-supplier-return-e2e.sql'),
 ('procurement_save_return_v1','enforced','procurement.supplier_return','Supplier return draft checks the supplier-return control, reason rule, max quantity, accepted-minus-returned and stock','Claude','B-012','tests/migrations/np03a-supplier-return-e2e.sql'),
 ('procurement_advance_return_v1','enforced','procurement.supplier_return','Supplier return post/cancel checks the supplier-return control, maker-checker and the stock master switch; stock only via post_stock_event','Claude','B-012','tests/migrations/np03a-supplier-return-e2e.sql');
