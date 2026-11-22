-- NP03A / B-012 (0204): Owner multi-business dashboard reads (Claude, block 0200-0299). Read-only, STABLE.
-- One owner -> many businesses -> many sites. Figures come only from the canonical books: stock balances (0200),
-- stock commands (0201), purchase orders and receipts (0203), the GOV-002 approval journal. Aggregates are computed
-- set-wise per business / per site (no per-row loops) so 10 businesses x 400 sites stay fast.
-- Scope: businesses where the caller is tenant owner, business owner or manager (can_business); site rows respect
-- explicit site denies (can_site stock.read). Pending approvals are shown only to those who may manage the business.
-- Sales, cash and receivables are NOT_CONNECTED here (NP03B / NP06 not on trunk); the screen says so plainly.

CREATE INDEX stock_balances_business_site_ix ON core10.stock_balances_v1 (business_id, site_id);
CREATE INDEX goods_receipts_business_status_ix ON core10.goods_receipts_v1 (business_id, status);
CREATE INDEX purchase_orders_business_status_ix ON core10.purchase_orders_v1 (business_id, status);

-- Businesses the caller may oversee: candidates from the caller's own memberships, then the Auth port decides.
CREATE FUNCTION core10._owner_businesses_v1() RETURNS TABLE(tenant_id bigint, business_id bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
 SELECT b.tenant_id, b.id FROM core10.businesses b
 WHERE (b.tenant_id IN (SELECT m.tenant_id FROM core10.tenant_members m WHERE m.user_id=core10.actor_uid() AND m.active)
     OR b.id IN (SELECT m.business_id FROM core10.business_members m WHERE m.user_id=core10.actor_uid() AND m.active))
   AND core10.can_business(b.tenant_id, b.id)
$$;

CREATE FUNCTION core10.owner_portfolio_v1() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v jsonb;
BEGIN
 IF core10.actor_uid() IS NULL THEN RAISE EXCEPTION 'DASH_UNAUTHENTICATED'; END IF;
 WITH ob AS (SELECT * FROM core10._owner_businesses_v1()),
 st AS (SELECT k.business_id, jsonb_object_agg(k.kind, k.n) AS by_kind
   FROM (SELECT business_id, kind, count(*) n FROM core10.sites WHERE business_id IN (SELECT business_id FROM ob) GROUP BY 1,2) k
   GROUP BY k.business_id),
 sc AS (SELECT business_id, count(*) AS sites FROM core10.sites WHERE business_id IN (SELECT business_id FROM ob) GROUP BY 1),
 bal AS (SELECT business_id, count(*) FILTER (WHERE on_hand>0) AS stock_rows, count(DISTINCT item_id) FILTER (WHERE on_hand>0) AS items,
   coalesce(sum(on_hand),0) AS units FROM core10.stock_balances_v1 WHERE business_id IN (SELECT business_id FROM ob) GROUP BY 1),
 po AS (SELECT business_id, count(*) FILTER (WHERE status IN ('approved','partially_received')) AS open_pos,
   coalesce(sum(total_amount) FILTER (WHERE status IN ('approved','partially_received')),0) AS open_amount,
   count(*) FILTER (WHERE status='draft') AS draft_pos
   FROM core10.purchase_orders_v1 WHERE business_id IN (SELECT business_id FROM ob) GROUP BY 1),
 gr AS (SELECT business_id, count(*) FILTER (WHERE status='received') AS awaiting_qc, count(*) FILTER (WHERE status='inspected') AS awaiting_post
   FROM core10.goods_receipts_v1 WHERE business_id IN (SELECT business_id FROM ob) AND status<>'posted' GROUP BY 1),
 cm AS (SELECT business_id, count(*) FILTER (WHERE status='draft') AS draft, count(*) FILTER (WHERE status='confirmed') AS confirmed
   FROM core10.inventory_commands_v1 WHERE business_id IN (SELECT business_id FROM ob) AND status IN ('draft','confirmed') GROUP BY 1),
 ap AS (SELECT business_id, count(*) AS pending FROM core10.approval_requests
   WHERE business_id IN (SELECT business_id FROM ob) AND status='pending' GROUP BY 1)
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'business_id',b.id,'tenant_id',b.tenant_id,'slug',b.slug,'template_code',b.template_code,
   'can_manage',core10.can_manage(b.tenant_id,b.id),
   'sites',coalesce(sc.sites,0),'sites_by_kind',coalesce(st.by_kind,'{}'::jsonb),
   'stock',jsonb_build_object('items',coalesce(bal.items,0),'stock_rows',coalesce(bal.stock_rows,0),'units',coalesce(bal.units,0)),
   'purchase',jsonb_build_object('open_pos',coalesce(po.open_pos,0),'open_amount',coalesce(po.open_amount,0),'draft_pos',coalesce(po.draft_pos,0),
     'awaiting_qc',coalesce(gr.awaiting_qc,0),'awaiting_post',coalesce(gr.awaiting_post,0)),
   'stock_commands',jsonb_build_object('draft',coalesce(cm.draft,0),'confirmed',coalesce(cm.confirmed,0)),
   'approvals_pending',CASE WHEN core10.can_manage(b.tenant_id,b.id) THEN coalesce(ap.pending,0) END,
   'not_connected',jsonb_build_array('sales','cash')) ORDER BY b.id),'[]'::jsonb)
 INTO v
 FROM ob JOIN core10.businesses b ON b.id=ob.business_id
 LEFT JOIN st ON st.business_id=b.id LEFT JOIN sc ON sc.business_id=b.id LEFT JOIN bal ON bal.business_id=b.id
 LEFT JOIN po ON po.business_id=b.id LEFT JOIN gr ON gr.business_id=b.id LEFT JOIN cm ON cm.business_id=b.id
 LEFT JOIN ap ON ap.business_id=b.id;
 RETURN jsonb_build_object('businesses',v,'generated_at',statement_timestamp());
END $$;

-- Drill-down: one business -> its sites (branch, factory, godown, warehouse, project), keyset pages <= 200.
CREATE FUNCTION core10.owner_business_sites_v1(p_business bigint, p_kind text DEFAULT NULL, p_after_site bigint DEFAULT NULL,
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
   WHERE business_id=p_business AND site_id IN (SELECT id FROM s) AND status<>'posted' GROUP BY 1),
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

REVOKE ALL ON FUNCTION core10._owner_businesses_v1() FROM PUBLIC, authenticated;
REVOKE ALL ON FUNCTION core10.owner_portfolio_v1(), core10.owner_business_sites_v1(bigint,text,bigint,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core10.owner_portfolio_v1(), core10.owner_business_sites_v1(bigint,text,bigint,integer) TO authenticated;
