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
  'sample_ids',to_jsonb((COALESCE(p_ids,ARRAY[]::bigint[]))[1:20]),'note',p_note) $$;

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

-- ===================== am_overview_v1 =====================
CREATE FUNCTION c10_demo.am_overview_v1(p_business bigint,p_site bigint DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c c10_demo.am_ctx_t; v_sites bigint[]; v_today date;
 a_status jsonb; a_site jsonb; wo_status jsonb; wo_prio jsonb; od jsonb; sla jsonb; tg jsonb; dt jsonb; cap jsonb;
BEGIN
 c:=c10_demo.ami_read_ctx(p_business);
 v_sites:=c10_demo.ami_rpt_scope(c,p_site,'reports');
 v_today:=c10_demo.ami_today(p_business);
 SELECT COALESCE(jsonb_object_agg(q.status,q.n),'{}'::jsonb) INTO a_status FROM
  (SELECT status,count(*) AS n FROM c10_demo.am_assets WHERE business_id=p_business AND site_id=ANY(v_sites) GROUP BY status) q;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('site_id',s.id,'label',s.label,'kind',s.kind,'total',COALESCE(x.total,0),
   'by_status',COALESCE(x.bs,'{}'::jsonb)) ORDER BY s.id),'[]'::jsonb) INTO a_site
  FROM c10_demo.sites s LEFT JOIN (SELECT q.site_id,sum(q.n) AS total,jsonb_object_agg(q.status,q.n) AS bs FROM
    (SELECT site_id,status,count(*) AS n FROM c10_demo.am_assets WHERE business_id=p_business AND site_id=ANY(v_sites) GROUP BY 1,2) q
    GROUP BY q.site_id) x ON x.site_id=s.id
  WHERE s.business_id=p_business AND s.id=ANY(v_sites);
 SELECT jsonb_build_object('DRAFT',count(*) FILTER (WHERE status='DRAFT'),'SUBMITTED',count(*) FILTER (WHERE status='SUBMITTED'),
   'APPROVED',count(*) FILTER (WHERE status='APPROVED'),'IN_PROGRESS',count(*) FILTER (WHERE status='IN_PROGRESS')),
  jsonb_build_object('low',count(*) FILTER (WHERE priority='low'),'medium',count(*) FILTER (WHERE priority='medium'),
   'high',count(*) FILTER (WHERE priority='high'),'critical',count(*) FILTER (WHERE priority='critical')),
  jsonb_build_object('count',count(*) FILTER (WHERE due_on<v_today),
   'sample_ids',to_jsonb(COALESCE((array_agg(id ORDER BY due_on,id) FILTER (WHERE due_on<v_today))[1:20],ARRAY[]::bigint[]))),
  jsonb_build_object(
   'resolve_breached',count(*) FILTER (WHERE sla_resolve_due_at<now()),
   'resolve_at_risk',count(*) FILTER (WHERE sla_resolve_due_at>=now() AND sla_resolve_due_at-now()<=(sla_resolve_due_at-requested_at)*0.25::float8),
   'response_breached',count(*) FILTER (WHERE sla_response_due_at<now() AND responded_at IS NULL AND started_at IS NULL),
   'resolve_breached_ids',to_jsonb(COALESCE((array_agg(id ORDER BY sla_resolve_due_at,id) FILTER (WHERE sla_resolve_due_at<now()))[1:20],ARRAY[]::bigint[])),
   'rule','open work orders; at_risk = remaining resolve time <= 25% of the resolve window')
  INTO wo_status,wo_prio,od,sla
  FROM c10_demo.am_work_orders WHERE business_id=p_business AND site_id=ANY(v_sites) AND status IN('DRAFT','SUBMITTED','APPROVED','IN_PROGRESS');
 SELECT jsonb_build_object('total',count(*),
   'by_state',jsonb_build_object('upcoming',count(*) FILTER (WHERE state='upcoming'),'due',count(*) FILTER (WHERE state='due'),
     'overdue',count(*) FILTER (WHERE state='overdue'),'meter_missing',count(*) FILTER (WHERE state='meter_missing'),
     'has_open_wo',count(*) FILTER (WHERE state='has_open_wo'),'deferred',count(*) FILTER (WHERE state='deferred')),
   'escalation',jsonb_build_object('level1',count(*) FILTER (WHERE escalation_level=1),'level2',count(*) FILTER (WHERE escalation_level=2)),
   'overdue_target_ids',to_jsonb(COALESCE((array_agg(target_id ORDER BY days_late DESC NULLS LAST,target_id) FILTER (WHERE overdue))[1:20],ARRAY[]::bigint[])),
   'rules','due: within lead days or inside grace; overdue: past due_on + grace; escalation 2: past grace + escalation_days')
  INTO tg FROM c10_demo.ami_rpt_targets(p_business,v_sites,v_today);
 SELECT jsonb_build_object('count',count(*),'items',COALESCE(jsonb_agg(jsonb_build_object('downtime_id',q.id,'asset_id',q.asset_id,
   'asset_no',q.asset_no,'site_id',q.site_id,'kind',q.kind,'work_order_id',q.work_order_id,'started_at',q.started_at,
   'open_hours',round(extract(epoch FROM now()-q.started_at)/3600.0,2),
   'exceeds_max_open',now()>q.started_at+make_interval(hours=>q.maxh)) ORDER BY q.started_at) FILTER (WHERE q.rn<=20),'[]'::jsonb))
  INTO dt FROM (SELECT d.id,d.asset_id,a.asset_no,a.site_id,d.kind,d.work_order_id,d.started_at,
    c10_demo.ami_cfg_int(p_business,a.site_id,a.category_id,'downtime.max_open_hours') AS maxh,
    row_number() OVER (ORDER BY d.started_at,d.id) AS rn
   FROM c10_demo.am_downtime d JOIN c10_demo.am_assets a ON a.id=d.asset_id
   WHERE d.business_id=p_business AND d.ended_at IS NULL AND a.site_id=ANY(v_sites)) q;
 cap:=jsonb_build_object('is_tenant_owner',c.is_tenant_owner,'is_business_owner',c.is_business_owner,
  'roles',(SELECT COALESCE(jsonb_agg(DISTINCT g->>'role'),'[]'::jsonb) FROM jsonb_array_elements(c.grants) g),
  'business_wide',to_jsonb(c10_demo.ami_caps(c,NULL)),
  'by_site',(SELECT COALESCE(jsonb_object_agg(s.id::text,to_jsonb(c10_demo.ami_caps(c,s.id))),'{}'::jsonb)
             FROM c10_demo.sites s WHERE s.business_id=p_business),
  'reports_sites',to_jsonb(v_sites));
 RETURN jsonb_build_object('business_id',p_business,'site_id',p_site,'sites',to_jsonb(v_sites),'as_of_date',v_today,
  'generated_at',now(),'assets_by_status',a_status,'assets_by_site',a_site,
  'open_work_orders',jsonb_build_object('by_status',wo_status,'by_priority',wo_prio,'total',
    (SELECT sum(v::int) FROM jsonb_each_text(wo_status) e(k,v))),
  'overdue_work_orders',od,'sla',sla,'plan_targets',tg,'open_downtime',dt,'capabilities',cap);
END$$;

-- ===================== am_downtime_report_v1 =====================
CREATE FUNCTION c10_demo.am_downtime_report_v1(p_business bigint,p_from date DEFAULT NULL,p_to date DEFAULT NULL,p_site bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c c10_demo.am_ctx_t; v_sites bigint[]; pe record; per_asset jsonb; per_site jsonb; top jsonb; tot jsonb; opn jsonb;
BEGIN
 c:=c10_demo.ami_read_ctx(p_business);
 v_sites:=c10_demo.ami_rpt_scope(c,p_site,'reports');
 SELECT * INTO pe FROM c10_demo.ami_rpt_period(p_business,p_from,p_to);
 SELECT COALESCE(jsonb_agg(jsonb_build_object('asset_id',x.asset_id,'asset_no',a.asset_no,'name',a.name,'site_id',x.site_id,
   'downtime_minutes',round(x.downtime_min,2),'windows',x.window_count,'merged_windows',x.island_count,
   'period_minutes',round(x.period_min,2),'availability_pct',round(100*(1-x.downtime_min/x.period_min),2),
   'exceeds_max_open',x.exceeds_max_open) ORDER BY x.downtime_min DESC,x.asset_id),'[]'::jsonb) INTO per_asset
  FROM (SELECT av.* FROM c10_demo.ami_rpt_avail(p_business,v_sites,pe.o_from_ts,pe.o_to_ts) av WHERE av.downtime_min>0
        ORDER BY av.downtime_min DESC,av.asset_id LIMIT 200) x JOIN c10_demo.am_assets a ON a.id=x.asset_id;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('site_id',q.site_id,'label',s.label,'assets',q.n,'downtime_minutes',round(q.dm,2),
   'windows',q.w,'period_minutes',round(q.pm,2),'availability_pct',round(100*(1-q.dm/q.pm),2)) ORDER BY q.site_id),'[]'::jsonb) INTO per_site
  FROM (SELECT av.site_id,count(*) AS n,sum(av.downtime_min) AS dm,sum(av.period_min) AS pm,sum(av.window_count) AS w
        FROM c10_demo.ami_rpt_avail(p_business,v_sites,pe.o_from_ts,pe.o_to_ts) av GROUP BY av.site_id) q
  JOIN c10_demo.sites s ON s.id=q.site_id;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('asset_id',x.asset_id,'asset_no',a.asset_no,'name',a.name,'site_id',x.site_id,
   'downtime_minutes',round(x.downtime_min,2),'share_pct',round(100*x.downtime_min/NULLIF(x.tot,0),2)) ORDER BY x.downtime_min DESC,x.asset_id),'[]'::jsonb)
  INTO top FROM (SELECT av.*,sum(av.downtime_min) OVER () AS tot FROM c10_demo.ami_rpt_avail(p_business,v_sites,pe.o_from_ts,pe.o_to_ts) av
        WHERE av.downtime_min>0 ORDER BY av.downtime_min DESC,av.asset_id LIMIT 5) x JOIN c10_demo.am_assets a ON a.id=x.asset_id;
 SELECT jsonb_build_object('downtime_minutes',round(COALESCE(sum(av.downtime_min),0),2),'period_minutes',round(COALESCE(sum(av.period_min),0),2),
   'assets_considered',count(*),'assets_with_downtime',count(*) FILTER (WHERE av.downtime_min>0),
   'counted_windows',COALESCE(sum(av.window_count),0),'merged_windows',COALESCE(sum(av.island_count),0),
   'fleet_availability_pct',CASE WHEN sum(av.period_min)>0 THEN round(100*(1-sum(av.downtime_min)/sum(av.period_min)),2) END)
  INTO tot FROM c10_demo.ami_rpt_avail(p_business,v_sites,pe.o_from_ts,pe.o_to_ts) av;
 SELECT tot||jsonb_build_object(
   'excluded_planned',count(*) FILTER (WHERE t.exclude_reason='planned_not_counted'),
   'excluded_below_min',count(*) FILTER (WHERE t.exclude_reason='below_min_minutes'),
   'open_windows',count(*) FILTER (WHERE t.is_open AND t.counted),
   'exceeds_max_open',count(*) FILTER (WHERE t.exceeds_max_open AND t.counted)),
  COALESCE(jsonb_agg(jsonb_build_object('downtime_id',t.downtime_id,'asset_id',t.asset_id,'started_at',t.started_at,
    'effective_end',t.eff_end,'exceeds_max_open',t.exceeds_max_open,
    'minutes_in_period',round(extract(epoch FROM t.seg_end-t.seg_start)/60.0,2)) ORDER BY t.started_at,t.downtime_id)
    FILTER (WHERE t.is_open),'[]'::jsonb)
  INTO tot,opn FROM c10_demo.ami_rpt_dt(p_business,v_sites,pe.o_from_ts,pe.o_to_ts) t;
 RETURN jsonb_build_object('business_id',p_business,'site_id',p_site,'sites',to_jsonb(v_sites),
  'period',jsonb_build_object('from',pe.o_from,'to',pe.o_to,'timezone',pe.o_tz),'generated_at',now(),
  'rules','windows clipped to the period; open windows end at LEAST(now, started+max_open_hours) and are flagged exceeds_max_open; planned downtime counted only when downtime.planned_counts; windows shorter than downtime.min_counted_minutes excluded; overlapping windows merged per asset; availability period clipped to commission/created date',
  'totals',tot,'per_asset',per_asset,'per_site',per_site,'top_offenders',top,'open_windows',opn);
END$$;

-- ===================== am_kpi_report_v1 =====================
CREATE FUNCTION c10_demo.am_kpi_report_v1(p_business bigint,p_from date DEFAULT NULL,p_to date DEFAULT NULL,p_site bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c c10_demo.am_ctx_t; v_sites bigint[]; pe record; v_today date;
 min_mttr int; min_mtbf int; win int; minrec int; hi int; cr int; md int;
 mttr_n int; mttr_h numeric; fail_n int; op_h numeric; per_asset jsonb; pm record; pm_j jsonb; od jsonb; sla jsonb; rec jsonb; risk jsonb; cost jsonb;
 win_end timestamptz;
BEGIN
 c:=c10_demo.ami_read_ctx(p_business);
 v_sites:=c10_demo.ami_rpt_scope(c,p_site,'reports');
 SELECT * INTO pe FROM c10_demo.ami_rpt_period(p_business,p_from,p_to);
 v_today:=c10_demo.ami_today(p_business);
 min_mttr:=c10_demo.ami_cfg_int(p_business,NULL,NULL,'analytics.min_sample_mttr');
 min_mtbf:=c10_demo.ami_cfg_int(p_business,NULL,NULL,'analytics.min_sample_mtbf');
 win:=c10_demo.ami_cfg_int(p_business,NULL,NULL,'analytics.recurring_window_days');
 minrec:=c10_demo.ami_cfg_int(p_business,NULL,NULL,'analytics.recurring_min_count');
 hi:=c10_demo.ami_cfg_int(p_business,NULL,NULL,'risk.high_threshold');
 cr:=c10_demo.ami_cfg_int(p_business,NULL,NULL,'risk.critical_threshold');
 md:=ceil(hi/2.0)::int;
 SELECT count(*),avg(r.repair_hours) INTO mttr_n,mttr_h FROM c10_demo.ami_rpt_repairs(p_business,v_sites,pe.o_from_ts,pe.o_to_ts) r;
 SELECT count(*) INTO fail_n FROM c10_demo.ami_rpt_failures(p_business,v_sites,pe.o_from_ts,pe.o_to_ts);
 SELECT COALESCE(sum(av.period_min-av.downtime_min),0)/60.0 INTO op_h FROM c10_demo.ami_rpt_avail(p_business,v_sites,pe.o_from_ts,pe.o_to_ts) av;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('asset_id',x.asset_id,'asset_no',x.asset_no,'name',x.name,'failures',x.failures,
   'repairs_sampled',x.repairs,
   'mttr_hours',CASE WHEN x.repairs>=min_mttr THEN round(x.rh,2) END,'mttr_insufficient_sample',x.repairs<min_mttr,
   'operating_hours',round(COALESCE(x.op,0),2),
   'mtbf_hours',CASE WHEN x.failures>=min_mtbf AND x.failures>0 THEN round(x.op/x.failures,2) END,'mtbf_insufficient_sample',x.failures<min_mtbf)
   ORDER BY x.failures DESC,x.asset_id),'[]'::jsonb) INTO per_asset
  FROM (SELECT a.id AS asset_id,a.asset_no,a.name,COALESCE(f.n,0)::int AS failures,COALESCE(r.n,0)::int AS repairs,r.h AS rh,av.op
        FROM c10_demo.am_assets a
        LEFT JOIN (SELECT ff.asset_id,count(*) AS n FROM c10_demo.ami_rpt_failures(p_business,v_sites,pe.o_from_ts,pe.o_to_ts) ff GROUP BY 1) f ON f.asset_id=a.id
        LEFT JOIN (SELECT rr.asset_id,count(*) AS n,avg(rr.repair_hours) AS h FROM c10_demo.ami_rpt_repairs(p_business,v_sites,pe.o_from_ts,pe.o_to_ts) rr GROUP BY 1) r ON r.asset_id=a.id
        LEFT JOIN (SELECT v.asset_id,(v.period_min-v.downtime_min)/60.0 AS op FROM c10_demo.ami_rpt_avail(p_business,v_sites,pe.o_from_ts,pe.o_to_ts) v) av ON av.asset_id=a.id
        WHERE a.business_id=p_business AND (f.n IS NOT NULL OR r.n IS NOT NULL) ORDER BY COALESCE(f.n,0) DESC,a.id LIMIT 200) x;
 SELECT * INTO pm FROM c10_demo.ami_rpt_pm(p_business,v_sites,pe.o_from,pe.o_to);
 pm_j:=jsonb_build_object('due',pm.due,'on_time',pm.on_time,'late',pm.late,'not_done',pm.not_done,
   'compliance_pct',CASE WHEN pm.due>0 THEN round(100.0*pm.on_time/pm.due,2) END,'insufficient_sample',pm.due=0,
   'rule','PM = preventive/inspection/calibration WOs due in period; compliant when completed on/before due_on + schedule.grace_days');
 SELECT jsonb_build_object('count',count(*),'as_of_date',v_today,
   'buckets',jsonb_build_object('1_7',count(*) FILTER (WHERE v_today-due_on BETWEEN 1 AND 7),'8_30',count(*) FILTER (WHERE v_today-due_on BETWEEN 8 AND 30),
     '31_90',count(*) FILTER (WHERE v_today-due_on BETWEEN 31 AND 90),'over_90',count(*) FILTER (WHERE v_today-due_on>90)),
   'oldest_days',max(v_today-due_on),
   'sample_ids',to_jsonb(COALESCE((array_agg(id ORDER BY due_on,id))[1:20],ARRAY[]::bigint[])))
  INTO od FROM c10_demo.am_work_orders WHERE business_id=p_business AND site_id=ANY(v_sites)
   AND status IN('DRAFT','SUBMITTED','APPROVED','IN_PROGRESS') AND due_on<v_today;
 SELECT jsonb_build_object(
   'resolve',jsonb_build_object('met',count(*) FILTER (WHERE q.rs='met'),'breached',count(*) FILTER (WHERE q.rs='breached'),
     'pending',count(*) FILTER (WHERE q.rs='pending'),
     'compliance_pct',CASE WHEN count(*) FILTER (WHERE q.rs IN('met','breached'))>0
       THEN round(100.0*count(*) FILTER (WHERE q.rs='met')/count(*) FILTER (WHERE q.rs IN('met','breached')),2) END),
   'response',jsonb_build_object('met',count(*) FILTER (WHERE q.ps='met'),'breached',count(*) FILTER (WHERE q.ps='breached'),
     'pending',count(*) FILTER (WHERE q.ps='pending'),
     'compliance_pct',CASE WHEN count(*) FILTER (WHERE q.ps IN('met','breached'))>0
       THEN round(100.0*count(*) FILTER (WHERE q.ps='met')/count(*) FILTER (WHERE q.ps IN('met','breached')),2) END),
   'population','non-cancelled work orders requested in the period')
  INTO sla FROM (SELECT
    CASE WHEN w.sla_resolve_due_at IS NULL THEN 'na'
         WHEN w.status IN('COMPLETED','VERIFIED','CLOSED') AND w.completed_at IS NOT NULL THEN CASE WHEN w.completed_at<=w.sla_resolve_due_at THEN 'met' ELSE 'breached' END
         WHEN w.sla_resolve_due_at<now() THEN 'breached' ELSE 'pending' END AS rs,
    CASE WHEN w.sla_response_due_at IS NULL THEN 'na'
         WHEN COALESCE(w.responded_at,w.started_at) IS NOT NULL THEN CASE WHEN COALESCE(w.responded_at,w.started_at)<=w.sla_response_due_at THEN 'met' ELSE 'breached' END
         WHEN w.sla_response_due_at<now() THEN 'breached' ELSE 'pending' END AS ps
   FROM c10_demo.am_work_orders w WHERE w.business_id=p_business AND w.site_id=ANY(v_sites) AND w.status<>'CANCELLED'
    AND w.merged_into_id IS NULL AND w.requested_at>=pe.o_from_ts AND w.requested_at<pe.o_to_ts) q;
 win_end:=LEAST(pe.o_to_ts,now());
 SELECT COALESCE(jsonb_agg(jsonb_build_object('asset_id',q.asset_id,'asset_no',q.asset_no,'failure_code',q.failure_code,'count',q.n,
   'first_at',q.f,'last_at',q.l,'wo_ids',to_jsonb(q.ids[1:20])) ORDER BY q.n DESC,q.asset_id,q.failure_code),'[]'::jsonb) INTO rec
  FROM (SELECT w.asset_id,a.asset_no,w.failure_code,count(*) AS n,min(w.requested_at) AS f,max(w.requested_at) AS l,array_agg(w.id ORDER BY w.id) AS ids
        FROM c10_demo.am_work_orders w JOIN c10_demo.am_assets a ON a.id=w.asset_id
        WHERE w.business_id=p_business AND a.site_id=ANY(v_sites) AND w.kind IN('breakdown','corrective') AND w.status<>'CANCELLED'
         AND w.merged_into_id IS NULL AND w.failure_code IS NOT NULL
         AND w.requested_at>win_end-make_interval(days=>win) AND w.requested_at<=win_end
        GROUP BY w.asset_id,a.asset_no,w.failure_code HAVING count(*)>=minrec) q;
 WITH f AS (SELECT ff.asset_id,count(*)::int AS n FROM c10_demo.ami_rpt_failures(p_business,v_sites,pe.o_from_ts,pe.o_to_ts) ff GROUP BY 1),
  r AS (SELECT a.id,a.asset_no,a.name,a.site_id,a.criticality::int AS crit,COALESCE(f.n,0) AS n,
         CASE WHEN COALESCE(f.n,0)=0 THEN 1 WHEN f.n=1 THEN 2 WHEN f.n=2 THEN 3 WHEN f.n<=4 THEN 4 ELSE 5 END AS lik
        FROM c10_demo.am_assets a LEFT JOIN f ON f.asset_id=a.id
        WHERE a.business_id=p_business AND a.site_id=ANY(v_sites) AND a.status NOT IN('retired','disposed','planned')),
  s AS (SELECT r.*,r.lik*r.crit AS score,
         CASE WHEN r.lik*r.crit>=cr THEN 'critical' WHEN r.lik*r.crit>=hi THEN 'high' WHEN r.lik*r.crit>=md THEN 'medium' ELSE 'low' END AS band,
         row_number() OVER (ORDER BY r.lik*r.crit DESC,r.id) AS rn FROM r)
 SELECT jsonb_build_object('thresholds',jsonb_build_object('medium',md,'high',hi,'critical',cr),
   'likelihood_rule','failure count in report period: 0->1, 1->2, 2->3, 3-4->4, 5+->5; score = likelihood x criticality',
   'bands',jsonb_build_object('low',count(*) FILTER (WHERE band='low'),'medium',count(*) FILTER (WHERE band='medium'),
     'high',count(*) FILTER (WHERE band='high'),'critical',count(*) FILTER (WHERE band='critical')),
   'matrix',(SELECT COALESCE(jsonb_agg(jsonb_build_object('likelihood',m.lik,'criticality',m.crit,'assets',m.n) ORDER BY m.lik,m.crit),'[]'::jsonb)
             FROM (SELECT s2.lik,s2.crit,count(*) AS n FROM s s2 GROUP BY s2.lik,s2.crit) m),
   'items',COALESCE(jsonb_agg(jsonb_build_object('asset_id',s.id,'asset_no',s.asset_no,'name',s.name,'site_id',s.site_id,'failures',s.n,
     'likelihood',s.lik,'criticality',s.crit,'score',s.score,'band',s.band) ORDER BY s.score DESC,s.id) FILTER (WHERE s.rn<=50),'[]'::jsonb))
  INTO risk FROM s;
 WITH w AS (SELECT * FROM c10_demo.am_work_orders w WHERE w.business_id=p_business AND w.site_id=ANY(v_sites)
            AND w.status IN('COMPLETED','VERIFIED','CLOSED') AND w.completed_at>=pe.o_from_ts AND w.completed_at<pe.o_to_ts)
 SELECT jsonb_build_object('advisory',true,'posted',false,'label','ADVISORY estimates from work-order lines; never posted to any ledger',
   'currency',c10_demo.ami_cfg_text(p_business,NULL,NULL,'general.currency'),'work_orders',count(*),
   'totals',jsonb_build_object('est_labor_cost',COALESCE(sum(est_labor_cost),0),'est_spares_cost',COALESCE(sum(est_spares_cost),0),
     'actual_labor_cost',COALESCE(sum(actual_labor_cost),0),'actual_spares_cost',COALESCE(sum(actual_spares_cost),0),
     'est_total',COALESCE(sum(est_labor_cost),0)+COALESCE(sum(est_spares_cost),0),
     'actual_total',COALESCE(sum(actual_labor_cost),0)+COALESCE(sum(actual_spares_cost),0)),
   'by_kind',(SELECT COALESCE(jsonb_object_agg(k.kind,jsonb_build_object('work_orders',k.n,'est_total',k.e,'actual_total',k.a)),'{}'::jsonb)
              FROM (SELECT kind,count(*) AS n,COALESCE(sum(est_labor_cost),0)+COALESCE(sum(est_spares_cost),0) AS e,
                    COALESCE(sum(actual_labor_cost),0)+COALESCE(sum(actual_spares_cost),0) AS a FROM w GROUP BY kind) k),
   'by_site',(SELECT COALESCE(jsonb_object_agg(k.site_id::text,jsonb_build_object('work_orders',k.n,'est_total',k.e,'actual_total',k.a)),'{}'::jsonb)
              FROM (SELECT site_id,count(*) AS n,COALESCE(sum(est_labor_cost),0)+COALESCE(sum(est_spares_cost),0) AS e,
                    COALESCE(sum(actual_labor_cost),0)+COALESCE(sum(actual_spares_cost),0) AS a FROM w GROUP BY site_id) k))
  INTO cost FROM w;
 RETURN jsonb_build_object('business_id',p_business,'site_id',p_site,'sites',to_jsonb(v_sites),
  'period',jsonb_build_object('from',pe.o_from,'to',pe.o_to,'timezone',pe.o_tz),'generated_at',now(),
  'mttr',jsonb_build_object('hours',CASE WHEN mttr_n>=min_mttr THEN round(mttr_h,2) END,'sample_size',mttr_n,'min_sample',min_mttr,
    'insufficient_sample',mttr_n<min_mttr),
  'mtbf',jsonb_build_object('hours',CASE WHEN fail_n>=min_mtbf AND fail_n>0 THEN round(op_h/fail_n,2) END,'operating_hours',round(op_h,2),
    'failures',fail_n,'min_sample',min_mtbf,'insufficient_sample',fail_n<min_mtbf),
  'per_asset',per_asset,'pm_compliance',pm_j,'overdue_backlog',od,'sla_compliance',sla,
  'recurring_failures',jsonb_build_object('window_days',win,'min_count',minrec,'items',rec),
  'risk_matrix',risk,'cost_rollup',cost);
END$$;

-- ===================== am_asset_health_report_v1 =====================
CREATE FUNCTION c10_demo.am_asset_health_report_v1(p_business bigint,p_site bigint DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c c10_demo.am_ctx_t; v_sites bigint[]; v_today date; v_win int; v_tz text; res jsonb;
BEGIN
 c:=c10_demo.ami_read_ctx(p_business);
 v_sites:=c10_demo.ami_rpt_scope(c,p_site,'reports');
 v_today:=c10_demo.ami_today(p_business);
 v_win:=c10_demo.ami_cfg_int(p_business,NULL,NULL,'analytics.recurring_window_days');
 v_tz:=c10_demo.ami_cfg_text(p_business,NULL,NULL,'general.timezone');
 WITH a AS (
   SELECT a.id,a.asset_no,a.name,a.site_id,a.status,a.criticality,a.category_id,a.acquisition_cost,
    cat.useful_life_months AS cul,cat.salvage_pct AS csal,
    COALESCE(a.commission_date,a.acquisition_date,(a.created_at AT TIME ZONE v_tz)::date) AS sd
   FROM c10_demo.am_assets a JOIN c10_demo.am_categories cat ON cat.id=a.category_id
   WHERE a.business_id=p_business AND a.site_id=ANY(v_sites) AND a.status NOT IN('retired','disposed','planned')),
  tg AS (SELECT t.asset_id,count(*) FILTER (WHERE t.overdue)::int AS n FROM c10_demo.ami_rpt_targets(p_business,v_sites,v_today) t GROUP BY t.asset_id),
  fl AS (SELECT f.asset_id,count(*)::int AS n FROM c10_demo.ami_rpt_failures(p_business,v_sites,now()-make_interval(days=>v_win),now()+interval '1 minute') f GROUP BY f.asset_id),
  mt AS (SELECT m.asset_id,count(*)::int AS n,
          count(*) FILTER (WHERE m.last_reading_at IS NULL OR m.last_reading_at<now()-make_interval(days=>c10_demo.ami_cfg_int(p_business,aa.site_id,aa.category_id,'meter.stale_days')))::int AS stale
         FROM c10_demo.am_meters m JOIN c10_demo.am_assets aa ON aa.id=m.asset_id
         WHERE m.business_id=p_business AND m.active AND aa.site_id=ANY(v_sites) GROUP BY m.asset_id),
  wr AS (SELECT w.asset_id,bool_or(w.expires_on>=v_today) AS act,bool_or(w.expires_on<v_today) AS expd
         FROM c10_demo.am_warranties w WHERE w.business_id=p_business AND w.status='active' GROUP BY w.asset_id),
  h AS (SELECT a.*,COALESCE(tg.n,0) AS n_od,COALESCE(fl.n,0) AS n_fl,COALESCE(mt.n,0) AS n_mt,COALESCE(mt.stale,0) AS n_stale,
         CASE WHEN COALESCE(wr.act,false) THEN 'active' WHEN COALESCE(wr.expd,false) THEN 'expired' ELSE 'none' END AS wstat,
         COALESCE(a.cul,c10_demo.ami_cfg_int(p_business,NULL,a.category_id,'finance.default_useful_life_months')) AS life,
         GREATEST(0,(v_today-a.sd))/30.4375 AS age_m,
         GREATEST(0,(extract(year FROM age(v_today::timestamp,a.sd::timestamp))*12+extract(month FROM age(v_today::timestamp,a.sd::timestamp)))::int) AS m_el,
         c10_demo.ami_cfg_text(p_business,NULL,a.category_id,'finance.depreciation_method') AS dm,
         COALESCE(a.csal,c10_demo.ami_cfg_num(p_business,NULL,a.category_id,'finance.default_salvage_pct')) AS salv_pct,
         c10_demo.ami_cfg_num(p_business,NULL,a.category_id,'finance.declining_rate_pct') AS rate
        FROM a LEFT JOIN tg ON tg.asset_id=a.id LEFT JOIN fl ON fl.asset_id=a.id LEFT JOIN mt ON mt.asset_id=a.id LEFT JOIN wr ON wr.asset_id=a.id),
  p AS (SELECT h.*,LEAST(30,10*h.n_od) AS p1,LEAST(30,8*h.n_fl) AS p2,
         LEAST(20,round(GREATEST(0,h.age_m/h.life-0.5)*40)::int) AS p3,
         CASE WHEN h.wstat='expired' THEN 5 ELSE 0 END AS p4,CASE WHEN h.n_stale>0 THEN 10 ELSE 0 END AS p5,
         round(h.acquisition_cost*h.salv_pct/100,2) AS salv_val FROM h),
  d AS (SELECT p.*,GREATEST(0,100-(p.p1+p.p2+p.p3+p.p4+p.p5)) AS score,
         CASE WHEN p.acquisition_cost IS NULL OR p.dm='none' THEN 0
              WHEN p.dm='declining_balance' THEN round(p.acquisition_cost-GREATEST(p.salv_val,p.acquisition_cost*power(1-p.rate/100,p.m_el/12.0)),2)
              ELSE round((p.acquisition_cost-p.salv_val)*LEAST(p.m_el,p.life)::numeric/p.life,2) END AS accum FROM p),
  z AS (SELECT d.*,CASE WHEN d.score>=80 THEN 'good' WHEN d.score>=60 THEN 'fair' WHEN d.score>=40 THEN 'poor' ELSE 'critical' END AS band,
         row_number() OVER (ORDER BY d.score,d.id) AS rn FROM d)
 SELECT jsonb_build_object('business_id',p_business,'site_id',p_site,'sites',to_jsonb(v_sites),'generated_at',now(),'as_of_date',v_today,
   'advisory',true,'total',count(*),'truncated',count(*)>200,
   'rules','score = 100 - penalties: overdue schedules (10 each, max 30), failures in recurring window (8 each, max 30), age vs useful life (0 until 50% of life, up to 20), expired warranty (5), stale meter (10)',
   'summary',jsonb_build_object('average_score',round(avg(score),1),
     'bands',jsonb_build_object('good',count(*) FILTER (WHERE band='good'),'fair',count(*) FILTER (WHERE band='fair'),
       'poor',count(*) FILTER (WHERE band='poor'),'critical',count(*) FILTER (WHERE band='critical')),
     'depreciation_advisory',jsonb_build_object('advisory',true,'posted',false,
       'total_accumulated',COALESCE(sum(accum),0),'total_book_value',COALESCE(sum(acquisition_cost-accum),0))),
   'items',COALESCE(jsonb_agg(jsonb_build_object('asset_id',id,'asset_no',asset_no,'name',name,'site_id',site_id,'status',status,
     'criticality',criticality,'health_score',score,'band',band,
     'components',jsonb_build_array(
       jsonb_build_object('key','overdue_schedules','label','Overdue schedules','value',n_od,'max_penalty',30,'penalty',p1),
       jsonb_build_object('key','recent_failures','label','Failures in recent window','value',n_fl,'window_days',v_win,'max_penalty',30,'penalty',p2),
       jsonb_build_object('key','age_vs_life','label','Age vs useful life','value',round(age_m/life,2),'age_months',round(age_m,1),'useful_life_months',life,'max_penalty',20,'penalty',p3),
       jsonb_build_object('key','warranty','label','Warranty status','value',wstat,'max_penalty',5,'penalty',p4),
       jsonb_build_object('key','meter_staleness','label','Meter staleness','value',n_stale,'meters',n_mt,'max_penalty',10,'penalty',p5)),
     'depreciation',jsonb_build_object('advisory',true,'posted',false,'method',dm,'useful_life_months',life,'salvage_pct',salv_pct,
       'acquisition_cost',acquisition_cost,'salvage_value',salv_val,'months_elapsed',m_el,'accumulated',CASE WHEN acquisition_cost IS NULL THEN NULL ELSE accum END,
       'book_value',CASE WHEN acquisition_cost IS NULL THEN NULL ELSE acquisition_cost-accum END,
       'reason',CASE WHEN acquisition_cost IS NULL THEN 'no_acquisition_cost' WHEN dm='none' THEN 'method_none' END))
     ORDER BY score,id) FILTER (WHERE rn<=200),'[]'::jsonb))
  INTO res FROM z;
 RETURN res;
END$$;

-- ===================== am_warranty_report_v1 =====================
CREATE FUNCTION c10_demo.am_warranty_report_v1(p_business bigint,p_horizon_days int DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c c10_demo.am_ctx_t; v_sites bigint[]; v_today date; v_tz text; minrec int; res jsonb; claims jsonb; rec jsonb;
BEGIN
 c:=c10_demo.ami_read_ctx(p_business);
 v_sites:=c10_demo.ami_rpt_scope(c,NULL,'reports');
 IF p_horizon_days IS NOT NULL AND (p_horizon_days<0 OR p_horizon_days>3650) THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 v_today:=c10_demo.ami_today(p_business);
 v_tz:=c10_demo.ami_cfg_text(p_business,NULL,NULL,'general.timezone');
 minrec:=c10_demo.ami_cfg_int(p_business,NULL,NULL,'analytics.recurring_min_count');
 WITH w0 AS (
  SELECT w.id AS wid,w.asset_id,a.asset_no,a.name,a.site_id,w.supplier_name,w.starts_on,w.expires_on,w.status AS wstatus,
    COALESCE(p_horizon_days,c10_demo.ami_cfg_int(p_business,a.site_id,a.category_id,'asset.warranty_warn_days')) AS horizon,
    (SELECT count(*) FROM c10_demo.am_warranty_claims cl WHERE cl.warranty_id=w.id) AS claims
  FROM c10_demo.am_warranties w JOIN c10_demo.am_assets a ON a.id=w.asset_id
  WHERE w.business_id=p_business AND a.site_id=ANY(v_sites)),
 w1 AS (SELECT w0.*,CASE WHEN w0.wstatus='void' THEN 'void' WHEN w0.expires_on<v_today THEN 'expired'
         WHEN w0.expires_on-v_today<=w0.horizon THEN 'expiring' ELSE 'active' END AS dstate FROM w0),
 w AS (SELECT w1.*,row_number() OVER (PARTITION BY w1.dstate ORDER BY w1.expires_on,w1.wid) AS rn,
        jsonb_build_object('warranty_id',w1.wid,'asset_id',w1.asset_id,'asset_no',w1.asset_no,'name',w1.name,'site_id',w1.site_id,
          'supplier_name',w1.supplier_name,'starts_on',w1.starts_on,'expires_on',w1.expires_on,'days_left',w1.expires_on-v_today,
          'horizon_days',w1.horizon,'claims',w1.claims,'state',w1.dstate) AS j FROM w1)
 SELECT jsonb_build_object('counts',jsonb_build_object('active',count(*) FILTER (WHERE dstate='active'),
    'expiring',count(*) FILTER (WHERE dstate='expiring'),'expired',count(*) FILTER (WHERE dstate='expired'),'void',count(*) FILTER (WHERE dstate='void')),
   'active',COALESCE(jsonb_agg(j ORDER BY expires_on,wid) FILTER (WHERE dstate='active' AND rn<=200),'[]'::jsonb),
   'expiring',COALESCE(jsonb_agg(j ORDER BY expires_on,wid) FILTER (WHERE dstate='expiring' AND rn<=200),'[]'::jsonb),
   'expired',COALESCE(jsonb_agg(j ORDER BY expires_on,wid) FILTER (WHERE dstate='expired' AND rn<=200),'[]'::jsonb))
  INTO res FROM w;
 SELECT jsonb_build_object('by_status',jsonb_build_object('draft',count(*) FILTER (WHERE cl.status='draft'),
    'submitted',count(*) FILTER (WHERE cl.status='submitted'),'accepted',count(*) FILTER (WHERE cl.status='accepted'),
    'rejected',count(*) FILTER (WHERE cl.status='rejected'),'settled',count(*) FILTER (WHERE cl.status='settled'),
    'closed',count(*) FILTER (WHERE cl.status='closed')),
   'advisory',true,'amount_claimed',COALESCE(sum(cl.amount_claimed),0),'amount_settled',COALESCE(sum(cl.amount_settled),0),'total',count(*))
  INTO claims FROM c10_demo.am_warranty_claims cl JOIN c10_demo.am_assets a ON a.id=cl.asset_id
  WHERE cl.business_id=p_business AND a.site_id=ANY(v_sites);
 SELECT COALESCE(jsonb_agg(jsonb_build_object('warranty_id',q.wid,'asset_id',q.asset_id,'asset_no',q.asset_no,'failure_code',q.failure_code,
    'count',q.n,'wo_ids',to_jsonb(q.ids[1:20])) ORDER BY q.n DESC,q.wid,q.failure_code),'[]'::jsonb) INTO rec
  FROM (SELECT w.id AS wid,w.asset_id,a.asset_no,o.failure_code,count(*) AS n,array_agg(o.id ORDER BY o.id) AS ids
        FROM c10_demo.am_warranties w JOIN c10_demo.am_assets a ON a.id=w.asset_id
        JOIN c10_demo.am_work_orders o ON o.asset_id=w.asset_id AND o.business_id=p_business
        WHERE w.business_id=p_business AND w.status='active' AND a.site_id=ANY(v_sites) AND o.kind IN('breakdown','corrective')
         AND o.status<>'CANCELLED' AND o.merged_into_id IS NULL AND o.failure_code IS NOT NULL
         AND (o.requested_at AT TIME ZONE v_tz)::date BETWEEN w.starts_on AND w.expires_on
        GROUP BY w.id,w.asset_id,a.asset_no,o.failure_code HAVING count(*)>=minrec) q;
 RETURN jsonb_build_object('business_id',p_business,'sites',to_jsonb(v_sites),'as_of_date',v_today,'generated_at',now(),
  'horizon_days',p_horizon_days,'horizon_source',CASE WHEN p_horizon_days IS NULL THEN 'policy asset.warranty_warn_days' ELSE 'request' END,
  'warranties',res,'claims',claims,'recurring_failures_in_warranty',jsonb_build_object('min_count',minrec,'items',rec));
END$$;

-- ===================== am_reconciliation_v1 =====================
CREATE FUNCTION c10_demo.am_reconciliation_v1(p_business bigint,p_from date DEFAULT NULL,p_to date DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c c10_demo.am_ctx_t; v_sites bigint[]; v_today date; pe record; v_lo timestamptz; v_hi timestamptz;
 i1 bigint[]; i2 bigint[]; i3 bigint[]; i4 bigint[]; i5 bigint[]; i6 bigint[]; i7 bigint[]; i8 bigint[]; i9 bigint[]; cls jsonb; tot int;
BEGIN
 c:=c10_demo.ami_read_ctx(p_business);
 v_sites:=c10_demo.ami_rpt_scope(c,NULL,'reports');
 v_today:=c10_demo.ami_today(p_business);
 IF p_from IS NOT NULL OR p_to IS NOT NULL THEN
  SELECT * INTO pe FROM c10_demo.ami_rpt_period(p_business,p_from,p_to); v_lo:=pe.o_from_ts; v_hi:=pe.o_to_ts; END IF;
 -- 1 completed breakdown WO without an ended downtime window (policy downtime.end_on: 'verified' waits for VERIFIED)
 SELECT COALESCE(array_agg(w.id ORDER BY w.id),ARRAY[]::bigint[]) INTO i1
  FROM c10_demo.am_work_orders w JOIN c10_demo.am_assets a ON a.id=w.asset_id
  WHERE w.business_id=p_business AND w.kind='breakdown' AND w.site_id=ANY(v_sites) AND w.merged_into_id IS NULL
   AND w.status IN('COMPLETED','VERIFIED','CLOSED')
   AND (w.status IN('VERIFIED','CLOSED') OR c10_demo.ami_cfg_text(p_business,w.site_id,a.category_id,'downtime.end_on')='completed')
   AND (NOT EXISTS(SELECT 1 FROM c10_demo.am_downtime d WHERE d.work_order_id=w.id AND d.ended_at IS NOT NULL)
        OR EXISTS(SELECT 1 FROM c10_demo.am_downtime d WHERE d.work_order_id=w.id AND d.ended_at IS NULL))
   AND (v_lo IS NULL OR (w.completed_at>=v_lo AND w.completed_at<v_hi));
 -- 2 breakdown downtime without a work order
 SELECT COALESCE(array_agg(d.id ORDER BY d.id),ARRAY[]::bigint[]) INTO i2
  FROM c10_demo.am_downtime d JOIN c10_demo.am_assets a ON a.id=d.asset_id
  WHERE d.business_id=p_business AND d.kind='breakdown' AND d.work_order_id IS NULL AND a.site_id=ANY(v_sites)
   AND (v_lo IS NULL OR (d.started_at>=v_lo AND d.started_at<v_hi));
 -- 3 asset status breakdown but no open downtime
 SELECT COALESCE(array_agg(a.id ORDER BY a.id),ARRAY[]::bigint[]) INTO i3
  FROM c10_demo.am_assets a WHERE a.business_id=p_business AND a.status='breakdown' AND a.site_id=ANY(v_sites)
   AND NOT EXISTS(SELECT 1 FROM c10_demo.am_downtime d WHERE d.asset_id=a.id AND d.ended_at IS NULL);
 -- 4 open downtime on an asset whose status is not breakdown/under_maintenance/idle
 SELECT COALESCE(array_agg(d.id ORDER BY d.id),ARRAY[]::bigint[]) INTO i4
  FROM c10_demo.am_downtime d JOIN c10_demo.am_assets a ON a.id=d.asset_id
  WHERE d.business_id=p_business AND d.ended_at IS NULL AND a.site_id=ANY(v_sites) AND a.status NOT IN('breakdown','under_maintenance','idle');
 -- 5 open WO on retired/disposed asset
 SELECT COALESCE(array_agg(w.id ORDER BY w.id),ARRAY[]::bigint[]) INTO i5
  FROM c10_demo.am_work_orders w JOIN c10_demo.am_assets a ON a.id=w.asset_id
  WHERE w.business_id=p_business AND w.status IN('DRAFT','SUBMITTED','APPROVED','IN_PROGRESS') AND a.status IN('retired','disposed')
   AND (w.site_id=ANY(v_sites) OR a.site_id=ANY(v_sites));
 -- 6 meter series decreasing without a reset (unless meter.allow_decrease)
 SELECT COALESCE(array_agg(q.id ORDER BY q.id),ARRAY[]::bigint[]) INTO i6
  FROM (SELECT r.id,r.kind,r.reading,r.read_at,lag(r.reading) OVER (PARTITION BY r.meter_id ORDER BY r.read_at,r.id) AS prev,m.asset_id
        FROM c10_demo.am_meter_readings r JOIN c10_demo.am_meters m ON m.id=r.meter_id WHERE r.business_id=p_business) q
  JOIN c10_demo.am_assets a ON a.id=q.asset_id
  WHERE q.kind='reading' AND q.prev IS NOT NULL AND q.reading<q.prev AND a.site_id=ANY(v_sites)
   AND NOT c10_demo.ami_cfg_bool(p_business,a.site_id,a.category_id,'meter.allow_decrease')
   AND (v_lo IS NULL OR (q.read_at>=v_lo AND q.read_at<v_hi));
 -- 7 scheduled plan target pointing at a closed (inactive/ended) plan
 SELECT COALESCE(array_agg(t.id ORDER BY t.id),ARRAY[]::bigint[]) INTO i7
  FROM c10_demo.am_plan_targets t JOIN c10_demo.am_plans p ON p.id=t.plan_id JOIN c10_demo.am_assets a ON a.id=t.asset_id
  WHERE t.business_id=p_business AND t.status='scheduled' AND a.site_id=ANY(v_sites)
   AND (NOT p.active OR (p.end_on IS NOT NULL AND p.end_on<v_today));
 -- 8 open WO whose site differs from the asset site
 SELECT COALESCE(array_agg(w.id ORDER BY w.id),ARRAY[]::bigint[]) INTO i8
  FROM c10_demo.am_work_orders w JOIN c10_demo.am_assets a ON a.id=w.asset_id
  WHERE w.business_id=p_business AND w.status IN('DRAFT','SUBMITTED','APPROVED','IN_PROGRESS') AND w.site_id<>a.site_id
   AND (w.site_id=ANY(v_sites) OR a.site_id=ANY(v_sites));
 -- 9 child asset at a different site than its parent
 SELECT COALESCE(array_agg(ch.id ORDER BY ch.id),ARRAY[]::bigint[]) INTO i9
  FROM c10_demo.am_assets ch JOIN c10_demo.am_assets pa ON pa.id=ch.parent_asset_id
  WHERE ch.business_id=p_business AND ch.site_id<>pa.site_id AND ch.status NOT IN('retired','disposed') AND ch.site_id=ANY(v_sites);
 cls:=jsonb_build_array(
  c10_demo.ami_rpt_cls('completed_breakdown_wo_without_ended_downtime','Completed breakdown work order without an ended downtime window','work_order',i1),
  c10_demo.ami_rpt_cls('breakdown_downtime_without_wo','Breakdown downtime without a work order','downtime',i2),
  c10_demo.ami_rpt_cls('asset_breakdown_without_open_downtime','Asset in breakdown status without open downtime','asset',i3),
  c10_demo.ami_rpt_cls('open_downtime_on_non_breakdown_asset','Open downtime on an asset that is not in breakdown/under_maintenance/idle status','downtime',i4),
  c10_demo.ami_rpt_cls('open_wo_on_retired_asset','Open work order on a retired or disposed asset','work_order',i5),
  c10_demo.ami_rpt_cls('meter_decrease_without_reset','Meter reading decreased without a reset','meter_reading',i6),
  c10_demo.ami_rpt_cls('plan_target_on_closed_plan','Scheduled plan target pointing to a closed plan','plan_target',i7),
  c10_demo.ami_rpt_cls('wo_site_differs_from_asset','Open work order site differs from asset site','work_order',i8),
  c10_demo.ami_rpt_cls('child_site_differs_from_parent','Child asset site differs from parent asset site','asset',i9));
 tot:=cardinality(i1)+cardinality(i2)+cardinality(i3)+cardinality(i4)+cardinality(i5)+cardinality(i6)+cardinality(i7)+cardinality(i8)+cardinality(i9);
 RETURN jsonb_build_object('business_id',p_business,'sites',to_jsonb(v_sites),'generated_at',now(),
  'period',CASE WHEN v_lo IS NULL THEN NULL ELSE jsonb_build_object('from',pe.o_from,'to',pe.o_to) END,
  'time_scoped_classes',jsonb_build_array('completed_breakdown_wo_without_ended_downtime','breakdown_downtime_without_wo','meter_decrease_without_reset'),
  'ok',tot=0,'total_mismatches',tot,'classes',cls);
END$$;

-- ===================== am_export_csv_v1 (write-ish: idempotent receipt + audit row 'export', contents never audited) =====================
CREATE FUNCTION c10_demo.am_export_csv_v1(p_business bigint,p_request text,p_kind text,p_params jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c c10_demo.am_ctx_t; rp jsonb; v_payload jsonb; v_p jsonb; k text; allowed text[]; v_sites bigint[]; v_site bigint;
 v_from date; v_to date; v_lo timestamptz; v_hi timestamptz; v_status text; v_entity text; v_eid text; v_max int; v_n int; v_body text;
 v_hdr text; v_trunc boolean; v_csv text; v_fn text; v_res jsonb; v_today date; v_tz text; v_sha text; v_pmax int; bg record;
BEGIN
 v_payload:=jsonb_build_object('kind',p_kind,'params',COALESCE(p_params,'{}'::jsonb));
 SELECT * INTO bg FROM c10_demo.ami_begin(p_business,p_request,'export_csv',v_payload);
 c:=bg.o_ctx; rp:=bg.o_replay;
 -- kind / params validation
 IF p_kind IS NULL OR p_kind NOT IN('assets','work_orders','downtime','schedule','warranty','audit') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 v_p:=COALESCE(p_params,'{}'::jsonb);
 IF jsonb_typeof(v_p)<>'object' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 allowed:=CASE p_kind WHEN 'assets' THEN ARRAY['site_id','status','max_rows'] WHEN 'work_orders' THEN ARRAY['site_id','status','from','to','max_rows']
   WHEN 'downtime' THEN ARRAY['site_id','from','to','max_rows'] WHEN 'schedule' THEN ARRAY['site_id','max_rows']
   WHEN 'warranty' THEN ARRAY['site_id','max_rows'] ELSE ARRAY['entity','entity_id','from','to','max_rows'] END;
 FOR k IN SELECT jsonb_object_keys(v_p) LOOP
  IF NOT (k=ANY(allowed)) THEN RAISE EXCEPTION 'am_invalid_input'; END IF; END LOOP;
 IF v_p?'site_id' THEN
  IF jsonb_typeof(v_p->'site_id')<>'number' OR (v_p->>'site_id') !~ '^[0-9]{1,12}$' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  v_site:=(v_p->>'site_id')::bigint; END IF;
 IF v_p?'max_rows' THEN
  IF jsonb_typeof(v_p->'max_rows')<>'number' OR (v_p->>'max_rows') !~ '^[0-9]{1,9}$' OR (v_p->>'max_rows')::bigint<1 THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  v_pmax:=LEAST((v_p->>'max_rows')::bigint,1000000000)::int; END IF;
 IF v_p?'from' THEN
  IF jsonb_typeof(v_p->'from')<>'string' OR (v_p->>'from') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  BEGIN v_from:=(v_p->>'from')::date; EXCEPTION WHEN others THEN RAISE EXCEPTION 'am_invalid_input'; END; END IF;
 IF v_p?'to' THEN
  IF jsonb_typeof(v_p->'to')<>'string' OR (v_p->>'to') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  BEGIN v_to:=(v_p->>'to')::date; EXCEPTION WHEN others THEN RAISE EXCEPTION 'am_invalid_input'; END; END IF;
 IF v_from IS NOT NULL AND v_to IS NOT NULL AND v_from>v_to THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF v_p?'status' THEN
  IF jsonb_typeof(v_p->'status')<>'string' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  v_status:=v_p->>'status';
  IF p_kind='assets' AND v_status NOT IN('planned','active','under_maintenance','breakdown','idle','retired','disposed') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  IF p_kind='work_orders' AND v_status NOT IN('DRAFT','SUBMITTED','APPROVED','IN_PROGRESS','COMPLETED','VERIFIED','CLOSED','CANCELLED') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 END IF;
 IF v_p?'entity' THEN
  IF jsonb_typeof(v_p->'entity')<>'string' OR length(v_p->>'entity') NOT BETWEEN 1 AND 60 THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  v_entity:=v_p->>'entity'; END IF;
 IF v_p?'entity_id' THEN
  IF jsonb_typeof(v_p->'entity_id')<>'string' OR length(v_p->>'entity_id') NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  v_eid:=v_p->>'entity_id'; END IF;
 -- authority (before replay / policy so a lost capability also blocks replays)
 IF p_kind='audit' THEN
  IF NOT c10_demo.ami_has(c,NULL,'audit_read') OR NOT c10_demo.ami_has(c,NULL,'export') THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
  v_sites:=ARRAY[]::bigint[];
 ELSE
  v_sites:=c10_demo.ami_rpt_scope(c,v_site,'export');
 END IF;
 IF NOT c10_demo.ami_cfg_bool(p_business,NULL,NULL,'export.csv_enabled') THEN RAISE EXCEPTION 'am_export_disabled'; END IF;
 IF rp IS NOT NULL THEN RETURN rp; END IF;
 v_max:=c10_demo.ami_cfg_int(p_business,NULL,NULL,'export.max_rows');
 IF v_pmax IS NOT NULL THEN v_max:=LEAST(v_max,v_pmax); END IF;
 v_tz:=c10_demo.ami_cfg_text(p_business,NULL,NULL,'general.timezone');
 v_today:=c10_demo.ami_today(p_business);
 IF v_from IS NOT NULL THEN v_lo:=v_from::timestamp AT TIME ZONE v_tz; END IF;
 IF v_to IS NOT NULL THEN v_hi:=(v_to+1)::timestamp AT TIME ZONE v_tz; END IF;

 IF p_kind='assets' THEN
  v_hdr:='asset_no,name,category_code,status,criticality,site_id,serial_no,model,manufacturer,ownership,acquisition_date,commission_date,acquisition_cost,parent_asset_no,quantity,version';
  SELECT count(*),COALESCE(string_agg(z.l,E'\r\n' ORDER BY z.id) FILTER (WHERE z.rn<=v_max),'') INTO v_n,v_body
  FROM (SELECT q.id,q.l,row_number() OVER (ORDER BY q.id) AS rn FROM
   (SELECT a.id,c10_demo.ami_csv_line(a.asset_no,a.name,ct.code,a.status,a.criticality::text,a.site_id::text,a.serial_no,a.model,a.manufacturer,
      a.ownership,a.acquisition_date::text,a.commission_date::text,a.acquisition_cost::text,pa.asset_no,a.quantity::text,a.version::text) AS l
    FROM c10_demo.am_assets a JOIN c10_demo.am_categories ct ON ct.id=a.category_id LEFT JOIN c10_demo.am_assets pa ON pa.id=a.parent_asset_id
    WHERE a.business_id=p_business AND a.site_id=ANY(v_sites) AND (v_status IS NULL OR a.status=v_status) ORDER BY a.id LIMIT v_max+1) q) z;
 ELSIF p_kind='work_orders' THEN
  v_hdr:='wo_no,kind,status,source,priority,asset_no,site_id,title,requested_at,due_on,started_at,completed_at,closed_at,failure_code,cause_code,action_code,est_labor_cost,est_spares_cost,actual_labor_cost,actual_spares_cost,sla_resolve_due_at,version';
  SELECT count(*),COALESCE(string_agg(z.l,E'\r\n' ORDER BY z.id) FILTER (WHERE z.rn<=v_max),'') INTO v_n,v_body
  FROM (SELECT q.id,q.l,row_number() OVER (ORDER BY q.id) AS rn FROM
   (SELECT w.id,c10_demo.ami_csv_line(w.wo_no,w.kind,w.status,w.source,w.priority,a.asset_no,w.site_id::text,w.title,c10_demo.ami_iso(w.requested_at),
      w.due_on::text,c10_demo.ami_iso(w.started_at),c10_demo.ami_iso(w.completed_at),c10_demo.ami_iso(w.closed_at),w.failure_code,w.cause_code,w.action_code,
      w.est_labor_cost::text,w.est_spares_cost::text,w.actual_labor_cost::text,w.actual_spares_cost::text,c10_demo.ami_iso(w.sla_resolve_due_at),w.version::text) AS l
    FROM c10_demo.am_work_orders w JOIN c10_demo.am_assets a ON a.id=w.asset_id
    WHERE w.business_id=p_business AND w.site_id=ANY(v_sites) AND (v_status IS NULL OR w.status=v_status)
     AND (v_lo IS NULL OR w.requested_at>=v_lo) AND (v_hi IS NULL OR w.requested_at<v_hi) ORDER BY w.id LIMIT v_max+1) q) z;
 ELSIF p_kind='downtime' THEN
  v_hdr:='downtime_id,asset_no,site_id,kind,reason_code,work_order_no,started_at,ended_at,minutes,open';
  SELECT count(*),COALESCE(string_agg(z.l,E'\r\n' ORDER BY z.id) FILTER (WHERE z.rn<=v_max),'') INTO v_n,v_body
  FROM (SELECT q.id,q.l,row_number() OVER (ORDER BY q.id) AS rn FROM
   (SELECT d.id,c10_demo.ami_csv_line(d.id::text,a.asset_no,a.site_id::text,d.kind,d.reason_code,w.wo_no,c10_demo.ami_iso(d.started_at),c10_demo.ami_iso(d.ended_at),
      CASE WHEN d.ended_at IS NOT NULL THEN round(extract(epoch FROM d.ended_at-d.started_at)/60.0)::text END,
      CASE WHEN d.ended_at IS NULL THEN 'true' ELSE 'false' END) AS l
    FROM c10_demo.am_downtime d JOIN c10_demo.am_assets a ON a.id=d.asset_id LEFT JOIN c10_demo.am_work_orders w ON w.id=d.work_order_id
    WHERE d.business_id=p_business AND a.site_id=ANY(v_sites) AND (v_lo IS NULL OR d.started_at>=v_lo) AND (v_hi IS NULL OR d.started_at<v_hi)
    ORDER BY d.id LIMIT v_max+1) q) z;
 ELSIF p_kind='schedule' THEN
  v_hdr:='target_id,plan_name,plan_type,asset_no,site_id,state,next_due_on,next_due_reading,last_done_on,days_late,escalation_level,deferred_until';
  SELECT count(*),COALESCE(string_agg(z.l,E'\r\n' ORDER BY z.id) FILTER (WHERE z.rn<=v_max),'') INTO v_n,v_body
  FROM (SELECT q.id,q.l,row_number() OVER (ORDER BY q.id) AS rn FROM
   (SELECT t.target_id AS id,c10_demo.ami_csv_line(t.target_id::text,t.plan_name,t.plan_type,a.asset_no,t.site_id::text,t.state,t.next_due_on::text,
      t.next_due_reading::text,pt.last_done_on::text,t.days_late::text,t.escalation_level::text,t.deferred_until::text) AS l
    FROM c10_demo.ami_rpt_targets(p_business,v_sites,v_today) t JOIN c10_demo.am_assets a ON a.id=t.asset_id
    JOIN c10_demo.am_plan_targets pt ON pt.id=t.target_id ORDER BY t.target_id LIMIT v_max+1) q) z;
 ELSIF p_kind='warranty' THEN
  v_hdr:='warranty_id,asset_no,site_id,supplier_name,supplier_ref,starts_on,expires_on,status,state,claims';
  SELECT count(*),COALESCE(string_agg(z.l,E'\r\n' ORDER BY z.id) FILTER (WHERE z.rn<=v_max),'') INTO v_n,v_body
  FROM (SELECT q.id,q.l,row_number() OVER (ORDER BY q.id) AS rn FROM
   (SELECT w.id,c10_demo.ami_csv_line(w.id::text,a.asset_no,a.site_id::text,w.supplier_name,w.supplier_ref,w.starts_on::text,w.expires_on::text,w.status,
      CASE WHEN w.status='void' THEN 'void' WHEN w.expires_on<v_today THEN 'expired'
           WHEN w.expires_on-v_today<=c10_demo.ami_cfg_int(p_business,a.site_id,a.category_id,'asset.warranty_warn_days') THEN 'expiring' ELSE 'active' END,
      (SELECT count(*) FROM c10_demo.am_warranty_claims cl WHERE cl.warranty_id=w.id)::text) AS l
    FROM c10_demo.am_warranties w JOIN c10_demo.am_assets a ON a.id=w.asset_id
    WHERE w.business_id=p_business AND a.site_id=ANY(v_sites) ORDER BY w.id LIMIT v_max+1) q) z;
 ELSE
  v_hdr:='audit_id,created_at,entity,entity_id,event,reason,actor_uid,request_key,before_state,after_state,row_hash';
  SELECT count(*),COALESCE(string_agg(z.l,E'\r\n' ORDER BY z.id) FILTER (WHERE z.rn<=v_max),'') INTO v_n,v_body
  FROM (SELECT q.id,q.l,row_number() OVER (ORDER BY q.id) AS rn FROM
   (SELECT x.id,c10_demo.ami_csv_line(x.id::text,c10_demo.ami_iso(x.created_at),x.entity,x.entity_id,x.event,x.reason,x.actor_uid::text,x.request_key,
      x.before_state::text,x.after_state::text,x.row_hash) AS l
    FROM c10_demo.am_audit x WHERE x.business_id=p_business AND (v_entity IS NULL OR x.entity=v_entity) AND (v_eid IS NULL OR x.entity_id=v_eid)
     AND (v_lo IS NULL OR x.created_at>=v_lo) AND (v_hi IS NULL OR x.created_at<v_hi) ORDER BY x.id LIMIT v_max+1) q) z;
 END IF;
 v_trunc:=v_n>v_max; v_n:=LEAST(v_n,v_max);
 v_csv:=v_hdr||E'\r\n'||CASE WHEN v_n>0 THEN v_body||E'\r\n' ELSE '' END;
 v_sha:=encode(sha256(convert_to(v_csv,'UTF8')),'hex');
 v_fn:=format('a055_%s_b%s_%s.csv',p_kind,p_business,to_char(now() AT TIME ZONE 'UTC','YYYYMMDD'));
 PERFORM c10_demo.ami_log(c.tenant_id,p_business,'export',p_request,'export',NULL,
   jsonb_build_object('kind',p_kind,'params',v_p,'rows',v_n,'truncated',v_trunc,'filename',v_fn,'sha256',v_sha),NULL,p_request);
 v_res:=jsonb_build_object('status','applied','kind',p_kind,'rows',v_n,'truncated',v_trunc,'max_rows',v_max,'filename',v_fn,'sha256',v_sha,
   'generated_at',now(),'csv',v_csv);
 RETURN c10_demo.ami_finish(p_business,c.tenant_id,p_request,'export_csv',v_payload,v_res);
END$$;

-- ===================== am_integrity_report_v1 (owner/auditor) =====================
-- TimeZone is pinned because ami_audit_hash hashes created_at::text, which depends on the session TimeZone.
CREATE FUNCTION c10_demo.am_integrity_report_v1(p_business bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog SET timezone='UTC' AS $$
DECLARE c c10_demo.am_ctx_t; r c10_demo.am_audit; prev text; v_ok boolean:=true; v_first bigint; v_reason text; n bigint:=0;
 o1 bigint; o2 bigint; o3 bigint; o4 bigint; o5 bigint; o6 bigint; rc bigint;
BEGIN
 c:=c10_demo.ami_read_ctx(p_business);
 IF NOT c10_demo.ami_has(c,NULL,'audit_read') THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
 FOR r IN SELECT * FROM c10_demo.am_audit WHERE business_id=p_business ORDER BY id LOOP
  n:=n+1;
  IF v_ok THEN
   IF r.tenant_id<>c.tenant_id THEN v_ok:=false; v_first:=r.id; v_reason:='tenant_mismatch';
   ELSIF r.prev_hash IS DISTINCT FROM prev THEN v_ok:=false; v_first:=r.id; v_reason:='prev_hash_mismatch';
   ELSIF r.row_hash IS DISTINCT FROM c10_demo.ami_audit_hash(prev,r) THEN v_ok:=false; v_first:=r.id; v_reason:='row_hash_mismatch'; END IF;
  END IF;
  prev:=r.row_hash;
 END LOOP;
 SELECT count(*) INTO rc FROM c10_demo.am_receipts WHERE business_id=p_business;
 SELECT count(*) INTO o1 FROM c10_demo.am_work_orders w WHERE w.business_id=p_business AND w.failure_code IS NOT NULL
   AND NOT EXISTS(SELECT 1 FROM c10_demo.am_codes k WHERE k.business_id=p_business AND k.kind='failure' AND k.code=w.failure_code);
 SELECT count(*) INTO o2 FROM c10_demo.am_work_orders w WHERE w.business_id=p_business AND w.cause_code IS NOT NULL
   AND NOT EXISTS(SELECT 1 FROM c10_demo.am_codes k WHERE k.business_id=p_business AND k.kind='cause' AND k.code=w.cause_code);
 SELECT count(*) INTO o3 FROM c10_demo.am_work_orders w WHERE w.business_id=p_business AND w.action_code IS NOT NULL
   AND NOT EXISTS(SELECT 1 FROM c10_demo.am_codes k WHERE k.business_id=p_business AND k.kind='action' AND k.code=w.action_code);
 SELECT count(*) INTO o4 FROM c10_demo.am_work_orders w WHERE w.business_id=p_business AND w.service_category IS NOT NULL
   AND NOT EXISTS(SELECT 1 FROM c10_demo.am_codes k WHERE k.business_id=p_business AND k.kind='service_category' AND k.code=w.service_category);
 SELECT count(*) INTO o5 FROM c10_demo.am_downtime d WHERE d.business_id=p_business AND d.reason_code IS NOT NULL
   AND NOT EXISTS(SELECT 1 FROM c10_demo.am_codes k WHERE k.business_id=p_business AND k.kind='downtime_reason' AND k.code=d.reason_code);
 SELECT count(*) INTO o6 FROM c10_demo.am_plans p WHERE p.business_id=p_business AND p.checklist_code IS NOT NULL
   AND NOT EXISTS(SELECT 1 FROM c10_demo.am_checklist_templates k WHERE k.business_id=p_business AND k.code=p.checklist_code);
 RETURN jsonb_build_object('business_id',p_business,'checked_at',now(),'ok',v_ok,'first_broken_audit_id',v_first,'reason',v_reason,
  'audit_rows',n,'receipts',rc,
  'orphans',jsonb_build_object('wo_failure_code',o1,'wo_cause_code',o2,'wo_action_code',o3,'wo_service_category',o4,
    'downtime_reason_code',o5,'plan_checklist_code',o6,'total',o1+o2+o3+o4+o5+o6),
  'orphans_ok',(o1+o2+o3+o4+o5+o6)=0);
END$$;

-- ===================== am_audit_log_v1 (owner/auditor) =====================
CREATE FUNCTION c10_demo.am_audit_log_v1(p_business bigint,p_entity text DEFAULT NULL,p_entity_id text DEFAULT NULL,
 p_limit int DEFAULT 50,p_offset int DEFAULT 0) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c c10_demo.am_ctx_t; v_lim int:=COALESCE(p_limit,50); v_off int:=COALESCE(p_offset,0); items jsonb; tot bigint;
BEGIN
 c:=c10_demo.ami_read_ctx(p_business);
 IF NOT c10_demo.ami_has(c,NULL,'audit_read') THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
 IF v_lim<1 OR v_lim>200 OR v_off<0 OR v_off>10000000 THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF (p_entity IS NOT NULL AND length(p_entity) NOT BETWEEN 1 AND 60) OR (p_entity_id IS NOT NULL AND length(p_entity_id) NOT BETWEEN 1 AND 100) THEN
  RAISE EXCEPTION 'am_invalid_input'; END IF;
 SELECT count(*) INTO tot FROM c10_demo.am_audit x WHERE x.business_id=p_business
  AND (p_entity IS NULL OR x.entity=p_entity) AND (p_entity_id IS NULL OR x.entity_id=p_entity_id);
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',q.id,'entity',q.entity,'entity_id',q.entity_id,'event',q.event,'before_state',q.before_state,
   'after_state',q.after_state,'reason',q.reason,'actor_uid',q.actor_uid,'request_key',q.request_key,'created_at',q.created_at,
   'prev_hash',q.prev_hash,'row_hash',q.row_hash) ORDER BY q.id DESC),'[]'::jsonb) INTO items
  FROM (SELECT * FROM c10_demo.am_audit x WHERE x.business_id=p_business
        AND (p_entity IS NULL OR x.entity=p_entity) AND (p_entity_id IS NULL OR x.entity_id=p_entity_id)
        ORDER BY x.id DESC LIMIT v_lim OFFSET v_off) q;
 RETURN jsonb_build_object('items',items,'total',tot,'limit',v_lim,'offset',v_off);
END$$;

-- ===================== read_asset_maintenance_business_summary_v1 (A050 adapter) =====================
CREATE FUNCTION c10_demo.read_asset_maintenance_business_summary_v1(p_business bigint,p_period date DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c c10_demo.am_ctx_t; v_sites bigint[]; v_today date; v_tz text; v_first date; v_last date; v_lo timestamptz; v_hi timestamptz;
 a_total bigint; a_status jsonb; wo jsonb; dt jsonb; pm record; cost jsonb; fleet numeric;
BEGIN
 c:=c10_demo.ami_read_ctx(p_business);
 PERFORM c10_demo.ami_need_owner(c);
 v_today:=c10_demo.ami_today(p_business);
 v_tz:=c10_demo.ami_cfg_text(p_business,NULL,NULL,'general.timezone');
 v_first:=date_trunc('month',COALESCE(p_period,v_today)::timestamp)::date;
 v_last:=(v_first+interval '1 month')::date-1;
 v_lo:=v_first::timestamp AT TIME ZONE v_tz; v_hi:=(v_last+1)::timestamp AT TIME ZONE v_tz;
 SELECT COALESCE(array_agg(s.id),ARRAY[]::bigint[]) INTO v_sites FROM c10_demo.sites s WHERE s.business_id=p_business;
 SELECT COALESCE(jsonb_object_agg(q.status,q.n),'{}'::jsonb),COALESCE(sum(q.n),0) INTO a_status,a_total
  FROM (SELECT status,count(*) AS n FROM c10_demo.am_assets WHERE business_id=p_business GROUP BY status) q;
 SELECT jsonb_build_object('created_in_period',count(*) FILTER (WHERE w.requested_at>=v_lo AND w.requested_at<v_hi),
   'completed_in_period',count(*) FILTER (WHERE w.completed_at>=v_lo AND w.completed_at<v_hi AND w.status IN('COMPLETED','VERIFIED','CLOSED')),
   'open_total',count(*) FILTER (WHERE w.status IN('DRAFT','SUBMITTED','APPROVED','IN_PROGRESS')),
   'overdue',count(*) FILTER (WHERE w.status IN('DRAFT','SUBMITTED','APPROVED','IN_PROGRESS') AND w.due_on<LEAST(v_last+1,v_today)),
   'open_breakdowns',count(*) FILTER (WHERE w.kind='breakdown' AND w.status IN('DRAFT','SUBMITTED','APPROVED','IN_PROGRESS')))
  INTO wo FROM c10_demo.am_work_orders w WHERE w.business_id=p_business AND w.status<>'CANCELLED';
 SELECT jsonb_build_object('downtime_minutes',round(COALESCE(sum(av.downtime_min),0),2),'period_minutes',round(COALESCE(sum(av.period_min),0),2),
   'availability_pct',CASE WHEN sum(av.period_min)>0 THEN round(100*(1-sum(av.downtime_min)/sum(av.period_min)),2) END,
   'assets_considered',count(*))
  INTO dt FROM c10_demo.ami_rpt_avail(p_business,v_sites,v_lo,v_hi) av;
 SELECT * INTO pm FROM c10_demo.ami_rpt_pm(p_business,v_sites,v_first,v_last);
 SELECT jsonb_build_object('advisory',true,'currency',c10_demo.ami_cfg_text(p_business,NULL,NULL,'general.currency'),
   'est_labor_cost',COALESCE(sum(est_labor_cost),0),'est_spares_cost',COALESCE(sum(est_spares_cost),0),
   'actual_labor_cost',COALESCE(sum(actual_labor_cost),0),'actual_spares_cost',COALESCE(sum(actual_spares_cost),0),
   'actual_total',COALESCE(sum(actual_labor_cost),0)+COALESCE(sum(actual_spares_cost),0))
  INTO cost FROM c10_demo.am_work_orders w WHERE w.business_id=p_business AND w.status IN('COMPLETED','VERIFIED','CLOSED')
   AND w.completed_at>=v_lo AND w.completed_at<v_hi;
 RETURN jsonb_build_object('contract','asset_maintenance.business_summary','contract_version','v1','business_id',p_business,
  'period',jsonb_build_object('month',to_char(v_first,'YYYY-MM'),'from',v_first,'to',v_last,'timezone',v_tz),'generated_at',now(),
  'advisory',true,'ledger_posted',false,'money_movement',false,
  'assets',jsonb_build_object('total',a_total,'by_status',a_status),'work_orders',wo,'downtime',dt,
  'pm_compliance',jsonb_build_object('due',pm.due,'on_time',pm.on_time,'late',pm.late,'not_done',pm.not_done,
    'compliance_pct',CASE WHEN pm.due>0 THEN round(100.0*pm.on_time/pm.due,2) END),
  'advisory_cost',cost);
END$$;
