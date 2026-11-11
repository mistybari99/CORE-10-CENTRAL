-- C10-A055 Enterprise Assets & Maintenance (6/7): REPORTS. Read-only analytics + guarded CSV export + audit/integrity.
-- DISPOSABLE c10_demo ONLY. Load after core (and the other feature files); before lockdown.
-- All reads are STABLE (no rows created, no locks), authorised through ami_read_ctx and FILTERED to the sites where the caller
-- holds capability 'reports' (export uses 'export', audit/integrity use business-wide 'audit_read').
-- Money values are ADVISORY: nothing here posts to a ledger, moves stock or touches payroll.
-- Conventions: WO-based metrics are scoped by work_orders.site_id; asset/downtime/meter/warranty metrics by the asset's CURRENT site.
-- Dates are interpreted in the business policy timezone (general.timezone).

-- ===================== internal helpers (ami_rpt_*) =====================
-- Sites the caller may report on (optionally narrowed to p_site). Unknown/foreign site => am_denied, no capability => am_not_permitted.
CREATE FUNCTION c10_demo.ami_rpt_scope(c c10_demo.am_ctx_t,p_site bigint,p_cap text) RETURNS bigint[]
LANGUAGE plpgsql STABLE AS $$
DECLARE v bigint[];
BEGIN
 IF p_site IS NOT NULL AND NOT EXISTS(SELECT 1 FROM c10_demo.sites s WHERE s.id=p_site AND s.business_id=c.business_id) THEN
  RAISE EXCEPTION 'am_denied'; END IF;
 v:=c10_demo.ami_sites_with(c,p_cap);
 IF cardinality(v)=0 AND NOT c10_demo.ami_has(c,NULL,p_cap) THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
 IF p_site IS NOT NULL THEN
  IF NOT (p_site=ANY(v)) THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
  RETURN ARRAY[p_site];
 END IF;
 RETURN v;
END$$;

CREATE FUNCTION c10_demo.ami_rpt_period(p_business bigint,p_from date,p_to date,OUT o_from date,OUT o_to date,
 OUT o_from_ts timestamptz,OUT o_to_ts timestamptz,OUT o_tz text) LANGUAGE plpgsql STABLE AS $$
BEGIN
 o_tz:=c10_demo.ami_cfg_text(p_business,NULL,NULL,'general.timezone');
 o_to:=COALESCE(p_to,c10_demo.ami_today(p_business));
 o_from:=COALESCE(p_from,o_to-29);
 IF o_from>o_to OR o_to-o_from>3660 THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 o_from_ts:=o_from::timestamp AT TIME ZONE o_tz;
 o_to_ts:=(o_to+1)::timestamp AT TIME ZONE o_tz;   -- exclusive end
END$$;

CREATE FUNCTION c10_demo.ami_iso(p timestamptz) RETURNS text LANGUAGE sql IMMUTABLE AS
$$ SELECT to_char(p AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"') $$;

CREATE FUNCTION c10_demo.ami_rpt_cls(p_code text,p_label text,p_entity text,p_ids bigint[],p_note text DEFAULT NULL) RETURNS jsonb
LANGUAGE sql IMMUTABLE AS $$
 SELECT jsonb_build_object('code',p_code,'label',p_label,'entity',p_entity,'count',cardinality(COALESCE(p_ids,ARRAY[]::bigint[])),
  'sample_ids',to_jsonb(COALESCE(p_ids,ARRAY[]::bigint[])[1:20]),'note',p_note) $$;

-- Downtime windows after policy (planned_counts, min_counted_minutes, max_open_hours) and clipping to [p_from,p_to).
CREATE FUNCTION c10_demo.ami_rpt_dt(p_business bigint,p_sites bigint[],p_from timestamptz,p_to timestamptz)
RETURNS TABLE(downtime_id bigint,asset_id bigint,site_id bigint,kind text,work_order_id bigint,started_at timestamptz,ended_at timestamptz,
 eff_end timestamptz,seg_start timestamptz,seg_end timestamptz,is_open boolean,exceeds_max_open boolean,counted boolean,exclude_reason text)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
BEGIN
 RETURN QUERY
 WITH b AS (
  SELECT d.id AS did,d.asset_id AS aid,a.site_id AS sid,d.kind AS k,d.work_order_id AS wid,d.started_at AS s,d.ended_at AS e,
   c10_demo.ami_cfg_int(p_business,a.site_id,a.category_id,'downtime.max_open_hours') AS maxh,
   c10_demo.ami_cfg_int(p_business,a.site_id,a.category_id,'downtime.min_counted_minutes') AS minm,
   c10_demo.ami_cfg_bool(p_business,a.site_id,a.category_id,'downtime.planned_counts') AS plc
  FROM c10_demo.am_downtime d JOIN c10_demo.am_assets a ON a.id=d.asset_id
  WHERE d.business_id=p_business AND a.business_id=p_business AND a.site_id=ANY(p_sites) AND d.started_at<p_to),
 x AS (SELECT b.*,COALESCE(b.e,GREATEST(b.s,LEAST(now(),b.s+make_interval(hours=>b.maxh)))) AS ee FROM b)
 SELECT x.did,x.aid,x.sid,x.k,x.wid,x.s,x.e,x.ee,GREATEST(x.s,p_from),LEAST(x.ee,p_to),(x.e IS NULL),
  (x.e IS NULL AND now()>x.s+make_interval(hours=>x.maxh)),
  (NOT (x.k='planned' AND NOT x.plc)) AND NOT (extract(epoch FROM x.ee-x.s)/60.0 < x.minm),
  CASE WHEN x.k='planned' AND NOT x.plc THEN 'planned_not_counted'
       WHEN extract(epoch FROM x.ee-x.s)/60.0 < x.minm THEN 'below_min_minutes' END
 FROM x WHERE x.ee>p_from;
END$$;

-- Per asset: period minutes (clipped to commission/created date, retirement, now) and MERGED (non-overlapping) counted downtime minutes.
CREATE FUNCTION c10_demo.ami_rpt_avail(p_business bigint,p_sites bigint[],p_from timestamptz,p_to timestamptz)
RETURNS TABLE(asset_id bigint,site_id bigint,period_min numeric,downtime_min numeric,window_count int,island_count int,exceeds_max_open boolean)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE tz text:=c10_demo.ami_cfg_text(p_business,NULL,NULL,'general.timezone');
BEGIN
 RETURN QUERY
 WITH seg AS (SELECT t.downtime_id AS did,t.asset_id AS aid,t.seg_start AS ss,t.seg_end AS se,t.exceeds_max_open AS ex
              FROM c10_demo.ami_rpt_dt(p_business,p_sites,p_from,p_to) t WHERE t.counted),
 o AS (SELECT s.*,max(s.se) OVER (PARTITION BY s.aid ORDER BY s.ss,s.did ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS pm FROM seg s),
 g AS (SELECT o.*,sum(CASE WHEN o.pm IS NULL OR o.ss>o.pm THEN 1 ELSE 0 END) OVER (PARTITION BY o.aid ORDER BY o.ss,o.did) AS grp FROM o),
 m AS (SELECT g.aid,g.grp,min(g.ss) AS ms,max(g.se) AS me,count(*) AS n,bool_or(g.ex) AS ex FROM g GROUP BY g.aid,g.grp),
 d AS (SELECT m.aid,sum(extract(epoch FROM m.me-m.ms))/60.0 AS mins,count(*)::int AS isl,sum(m.n)::int AS win,bool_or(m.ex) AS ex FROM m GROUP BY m.aid),
 p AS (SELECT a.id AS aid,a.site_id AS sid,
   GREATEST(0,extract(epoch FROM LEAST(p_to,now(),COALESCE(a.retired_at,p_to))
     - GREATEST(p_from,COALESCE(a.commission_date::timestamp AT TIME ZONE tz,a.created_at)))/60.0) AS pmin
  FROM c10_demo.am_assets a WHERE a.business_id=p_business AND a.site_id=ANY(p_sites) AND a.status<>'planned')
 SELECT p.aid,p.sid,p.pmin::numeric,LEAST(COALESCE(d.mins,0),p.pmin)::numeric,COALESCE(d.win,0),COALESCE(d.isl,0),COALESCE(d.ex,false)
 FROM p LEFT JOIN d ON d.aid=p.aid WHERE p.pmin>0;
END$$;

-- Failure events = breakdown work orders (not cancelled / merged) whose failure time (downtime start, else requested_at) is in [p_from,p_to).
CREATE FUNCTION c10_demo.ami_rpt_failures(p_business bigint,p_sites bigint[],p_from timestamptz,p_to timestamptz)
RETURNS TABLE(wo_id bigint,asset_id bigint,site_id bigint,failure_ts timestamptz,failure_code text,wo_status text)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
BEGIN
 RETURN QUERY
 SELECT w.id,w.asset_id,a.site_id,COALESCE(dt.fs,w.requested_at),w.failure_code,w.status
 FROM c10_demo.am_work_orders w JOIN c10_demo.am_assets a ON a.id=w.asset_id
 LEFT JOIN LATERAL (SELECT min(d.started_at) AS fs FROM c10_demo.am_downtime d WHERE d.work_order_id=w.id) dt ON true
 WHERE w.business_id=p_business AND w.kind='breakdown' AND w.status<>'CANCELLED' AND w.merged_into_id IS NULL
  AND a.site_id=ANY(p_sites) AND COALESCE(dt.fs,w.requested_at)>=p_from AND COALESCE(dt.fs,w.requested_at)<p_to;
END$$;

-- Repairs for MTTR: completed breakdown WOs completed in [p_from,p_to). Start = first linked downtime start, else WO started_at;
-- end = restore time (last linked downtime end, when all linked windows are closed), else completed_at.
CREATE FUNCTION c10_demo.ami_rpt_repairs(p_business bigint,p_sites bigint[],p_from timestamptz,p_to timestamptz)
RETURNS TABLE(wo_id bigint,asset_id bigint,repair_hours numeric)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
BEGIN
 RETURN QUERY
 SELECT q.wid,q.aid,(extract(epoch FROM q.re-q.rs)/3600.0)::numeric
 FROM (SELECT w.id AS wid,w.asset_id AS aid,COALESCE(dt.fs,w.started_at) AS rs,
        COALESCE(CASE WHEN dt.any_open IS FALSE THEN dt.le END,w.completed_at) AS re
       FROM c10_demo.am_work_orders w JOIN c10_demo.am_assets a ON a.id=w.asset_id
       LEFT JOIN LATERAL (SELECT min(d.started_at) AS fs,max(d.ended_at) AS le,bool_or(d.ended_at IS NULL) AS any_open
                          FROM c10_demo.am_downtime d WHERE d.work_order_id=w.id) dt ON true
       WHERE w.business_id=p_business AND w.kind='breakdown' AND w.status IN('COMPLETED','VERIFIED','CLOSED')
        AND w.completed_at IS NOT NULL AND w.completed_at>=p_from AND w.completed_at<p_to AND w.merged_into_id IS NULL
        AND a.site_id=ANY(p_sites)) q
 WHERE q.rs IS NOT NULL AND q.re IS NOT NULL AND q.re>=q.rs;
END$$;

-- Planned-maintenance compliance. PM kinds = preventive, inspection, calibration. Denominator = non-cancelled PM WOs with due_on in the
-- period; numerator = completed on/before due_on + schedule.grace_days (policy by site/category).
CREATE FUNCTION c10_demo.ami_rpt_pm(p_business bigint,p_sites bigint[],p_from date,p_to date)
RETURNS TABLE(due int,on_time int,late int,not_done int) LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE tz text:=c10_demo.ami_cfg_text(p_business,NULL,NULL,'general.timezone');
BEGIN
 RETURN QUERY
 SELECT count(*)::int,count(*) FILTER (WHERE q.done AND q.cd<=q.due_on+q.grace)::int,
  count(*) FILTER (WHERE q.done AND q.cd>q.due_on+q.grace)::int,count(*) FILTER (WHERE NOT q.done)::int
 FROM (SELECT w.due_on,c10_demo.ami_cfg_int(p_business,w.site_id,a.category_id,'schedule.grace_days') AS grace,
        (w.status IN('COMPLETED','VERIFIED','CLOSED') AND w.completed_at IS NOT NULL) AS done,
        (w.completed_at AT TIME ZONE tz)::date AS cd
       FROM c10_demo.am_work_orders w JOIN c10_demo.am_assets a ON a.id=w.asset_id
       WHERE w.business_id=p_business AND w.kind IN('preventive','inspection','calibration') AND w.status<>'CANCELLED'
        AND w.merged_into_id IS NULL AND w.due_on BETWEEN p_from AND p_to AND w.site_id=ANY(p_sites)) q;
END$$;

-- Due-state of plan targets (same rules as the planner; computed independently, no planning function is called).
-- precedence: deferred > has_open_wo > meter_missing > overdue > due > upcoming. days_late=today-next_due_on; due when within
-- lead window or inside grace; overdue when days_late>grace; escalation 1 when overdue, 2 when days_late>grace+escalation_days.
CREATE FUNCTION c10_demo.ami_rpt_targets(p_business bigint,p_sites bigint[],p_today date)
RETURNS TABLE(target_id bigint,plan_id bigint,plan_name text,plan_type text,asset_id bigint,site_id bigint,frequency_kind text,
 next_due_on date,next_due_reading numeric,current_reading numeric,deferred_until date,days_late int,overdue boolean,state text,
 escalation_level int,has_open_wo boolean)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
BEGIN
 RETURN QUERY
 WITH b AS (
  SELECT t.id AS tid,p.id AS pid,p.name AS pname,p.plan_type AS ptype,t.asset_id AS aid,a.site_id AS sid,p.frequency_kind AS fk,
   t.next_due_on AS ndo,t.next_due_reading AS ndr,m.current_reading AS cr,m.id AS mid,t.deferred_until AS du,
   COALESCE(p.lead_days,c10_demo.ami_cfg_int(p_business,a.site_id,a.category_id,'schedule.due_lead_days')) AS lead,
   c10_demo.ami_cfg_int(p_business,a.site_id,a.category_id,'schedule.grace_days') AS grace,
   c10_demo.ami_cfg_int(p_business,a.site_id,a.category_id,'schedule.escalation_days') AS esc,
   EXISTS(SELECT 1 FROM c10_demo.am_work_orders w WHERE w.plan_target_id=t.id AND w.status NOT IN('CLOSED','CANCELLED')) AS ow
  FROM c10_demo.am_plan_targets t JOIN c10_demo.am_plans p ON p.id=t.plan_id JOIN c10_demo.am_assets a ON a.id=t.asset_id
  LEFT JOIN LATERAL (SELECT m2.id,m2.current_reading FROM c10_demo.am_meters m2
                     WHERE m2.asset_id=a.id AND m2.code=p.meter_code AND m2.active ORDER BY m2.id LIMIT 1) m ON true
  WHERE t.business_id=p_business AND a.site_id=ANY(p_sites) AND t.status='scheduled' AND p.active
   AND (p.end_on IS NULL OR p.end_on>=p_today) AND a.status NOT IN('retired','disposed')),
 c AS (SELECT b.*,CASE WHEN b.fk<>'usage' AND b.ndo IS NOT NULL THEN p_today-b.ndo END AS late FROM b)
 SELECT c.tid,c.pid,c.pname,c.ptype,c.aid,c.sid,c.fk,c.ndo,c.ndr,c.cr,c.du,c.late,
  ((c.du IS NULL OR c.du<=p_today) AND c.late IS NOT NULL AND c.late>c.grace),
  CASE WHEN c.du IS NOT NULL AND c.du>p_today THEN 'deferred'
       WHEN c.ow THEN 'has_open_wo'
       WHEN c.fk='usage' AND c.mid IS NULL THEN 'meter_missing'
       WHEN c.fk='usage' THEN CASE WHEN c.ndr IS NOT NULL AND c.cr>=c.ndr THEN 'due' ELSE 'upcoming' END
       WHEN c.late IS NULL THEN 'upcoming'
       WHEN c.late>c.grace THEN 'overdue'
       WHEN c.late>=-c.lead THEN 'due' ELSE 'upcoming' END,
  CASE WHEN (c.du IS NOT NULL AND c.du>p_today) OR c.late IS NULL OR c.late<=c.grace THEN 0
       WHEN c.late>c.grace+c.esc THEN 2 ELSE 1 END,
  c.ow
 FROM c;
END$$;

-- ---- CSV primitives (RFC 4180 + spreadsheet formula-injection guard) ----
-- A cell whose first non-space character is = + - @ TAB CR (or LF) is prefixed with an apostrophe; then quoted when it contains
-- comma, double quote, CR or LF (embedded newlines stay inside the quotes).
CREATE FUNCTION c10_demo.ami_csv_cell(p text) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE t text; f text;
BEGIN
 IF p IS NULL THEN RETURN ''; END IF;
 t:=p; f:=left(ltrim(t,' '),1);
 IF f<>'' AND f IN('=','+','-','@',E'\t',E'\r',E'\n') THEN t:=''''||t; END IF;
 IF t ~ E'[",\r\n]' THEN t:='"'||replace(t,'"','""')||'"'; END IF;
 RETURN t;
END$$;
CREATE FUNCTION c10_demo.ami_csv_line(VARIADIC p text[]) RETURNS text LANGUAGE sql IMMUTABLE AS
$$ SELECT string_agg(c10_demo.ami_csv_cell(x),',' ORDER BY o) FROM unnest(p) WITH ORDINALITY u(x,o) $$;

