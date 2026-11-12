
-- Build05 scoped durable paint recipe/ticket/QC slice; DISPOSABLE POSTGRES 17 ONLY.
-- Requires shared A018-style c10_demo.businesses / actor_uid / can_manage contracts.
-- No direct stock, sale, cash, journal or external writes. NO production migration.
DO $gate$
BEGIN
 IF current_database() !~ '^core10_paint_(ci|local)$' THEN
   RAISE EXCEPTION 'BUILD05_DISPOSABLE_DB_ONLY';
 END IF;
 IF to_regclass('c10_demo.businesses') IS NULL
   OR to_regprocedure('c10_demo.actor_uid()') IS NULL
   OR to_regprocedure('c10_demo.can_manage(bigint,bigint)') IS NULL THEN
   RAISE EXCEPTION 'BUILD05_CANONICAL_SCOPE_REQUIRED';
 END IF;
END $gate$;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE c10_demo.paint_formula_v1(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 shade_code text NOT NULL CHECK(shade_code ~ '^[A-Za-z0-9_-]{2,48}$'),
 formula_version int NOT NULL CHECK(formula_version BETWEEN 1 AND 9999),
 base_sku text NOT NULL CHECK(base_sku ~ '^[A-Za-z0-9_-]{2,48}$'),
 output_sku text NOT NULL CHECK(output_sku ~ '^[A-Za-z0-9_-]{2,48}$'),
 pigments jsonb NOT NULL,
 qc_max_de100 int NOT NULL CHECK(qc_max_de100 BETWEEN 0 AND 2000),
 tolerance_bps int NOT NULL CHECK(tolerance_bps BETWEEN 0 AND 1000),
 created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (business_id,shade_code,formula_version),
 UNIQUE (id,tenant_id,business_id),
 FOREIGN KEY (business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id)
);
CREATE TABLE c10_demo.paint_tint_v1(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 ticket_key text NOT NULL CHECK(ticket_key ~ '^[A-Za-z0-9_-]{2,48}$'),
 formula_id bigint NOT NULL,
 base_ml int NOT NULL CHECK(base_ml BETWEEN 100 AND 200000),
 status text NOT NULL DEFAULT 'DRAFT' CHECK(status IN('DRAFT','MIXED','QC_FAILED','QC_PASSED')),
 version int NOT NULL DEFAULT 1,
 created_by uuid NOT NULL,
 mixed_by uuid,
 mix_data jsonb,
 qc_by uuid,
 qc_delta_e100 int,
 qc_method text,
 qc_instrument_ref text,
 qc_evidence_ref text,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (business_id,ticket_key),
 UNIQUE (id,tenant_id,business_id),
 FOREIGN KEY(formula_id,tenant_id,business_id) REFERENCES c10_demo.paint_formula_v1(id,tenant_id,business_id),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id)
);
CREATE TABLE c10_demo.paint_receipt_v1(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 request_key text NOT NULL CHECK(request_key ~ '^[A-Za-z0-9_-]{8,100}$'),
 actor uuid NOT NULL,
 command text NOT NULL,
 payload_hash text NOT NULL,
 response jsonb NOT NULL DEFAULT '{}'::jsonb,
 UNIQUE(business_id,request_key),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id)
);
CREATE TABLE c10_demo.paint_events_v1(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 ticket_id bigint,
 formula_id bigint,
 event text NOT NULL CHECK(event IN ('FORMULA_CREATED','TICKET_OPENED','MIX_RECORDED','QC_RECORDED')),
 actor uuid NOT NULL,
 request_key text NOT NULL,
 details jsonb NOT NULL DEFAULT '{}'::jsonb,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (business_id,request_key),
 FOREIGN KEY (business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id),
 FOREIGN KEY (ticket_id,tenant_id,business_id) REFERENCES c10_demo.paint_tint_v1(id,tenant_id,business_id),
 FOREIGN KEY (formula_id,tenant_id,business_id) REFERENCES c10_demo.paint_formula_v1(id,tenant_id,business_id)
);
ALTER TABLE c10_demo.paint_formula_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE c10_demo.paint_tint_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE c10_demo.paint_receipt_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE c10_demo.paint_events_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON c10_demo.paint_formula_v1,c10_demo.paint_tint_v1,c10_demo.paint_receipt_v1,c10_demo.paint_events_v1 FROM PUBLIC,anon,authenticated;

-- This procedural adapter accepts only structured industry commands;
-- it cannot create stock movement, sale, invoice, or financial journal entries.
CREATE OR REPLACE FUNCTION c10_demo.paint_command_v1(
 p_business bigint,p_command text,p_payload jsonb,p_request text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE
 v_tenant bigint; v_actor uuid; v_hash text; v_receipt c10_demo.paint_receipt_v1%ROWTYPE;
 v_formula c10_demo.paint_formula_v1%ROWTYPE; v_ticket c10_demo.paint_tint_v1%ROWTYPE;
 v_item jsonb; v_sku text; v_value int; v_sum int := 0; v_count int := 0;
 v_actual jsonb; v_seen text[] := '{}'::text[]; v_expected numeric; v_actual_ul int;
 v_result jsonb; v_id bigint; v_pass boolean; v_method text; v_instrument text; v_evidence text;
BEGIN
 v_actor:=c10_demo.actor_uid();
 SELECT tenant_id INTO v_tenant FROM c10_demo.businesses WHERE id=p_business;
 IF v_actor IS NULL OR v_tenant IS NULL OR
    NOT c10_demo.can_manage(v_tenant,p_business) THEN
    RAISE EXCEPTION 'PAINT_SCOPE_DENIED';
 END IF;
 IF p_command IS NULL OR p_command NOT IN('recipe','open','mix','qc') OR
    p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR
    p_request IS NULL OR p_request !~ '^[A-Za-z0-9_-]{8,100}$' THEN
    RAISE EXCEPTION 'PAINT_INVALID_COMMAND';
 END IF;
 v_hash:=encode(digest(p_command||':'||p_payload::text,'sha256'),'hex');
 INSERT INTO c10_demo.paint_receipt_v1(tenant_id,business_id,request_key,actor,command,payload_hash)
 VALUES(v_tenant,p_business,p_request,v_actor,p_command,v_hash)
 ON CONFLICT(business_id,request_key) DO NOTHING;
 SELECT * INTO v_receipt FROM c10_demo.paint_receipt_v1
 WHERE business_id=p_business AND request_key=p_request FOR UPDATE;
 IF v_receipt.actor<>v_actor OR v_receipt.command<>p_command OR v_receipt.payload_hash<>v_hash
 THEN RAISE EXCEPTION 'PAINT_REPLAY_CONFLICT'; END IF;
 IF v_receipt.response<>'{}'::jsonb THEN RETURN v_receipt.response; END IF;

 IF p_command='recipe' THEN
   IF p_payload->>'code' !~ '^[A-Za-z0-9_-]{2,48}$' OR
      p_payload->>'baseSku' !~ '^[A-Za-z0-9_-]{2,48}$' OR
      p_payload->>'outputSku' !~ '^[A-Za-z0-9_-]{2,48}$' OR
      jsonb_typeof(p_payload->'pigments')<>'array' OR
      jsonb_array_length(p_payload->'pigments') NOT BETWEEN 1 AND 32 OR
      (p_payload->>'version') !~ '^[0-9]{1,4}$' OR
      (p_payload->>'qcMaxDE100') !~ '^[0-9]{1,4}$' OR
      (p_payload->>'toleranceBps') !~ '^[0-9]{1,4}$' THEN
      RAISE EXCEPTION 'PAINT_INVALID_RECIPE';
   END IF;
   IF (p_payload->>'version')::int NOT BETWEEN 1 AND 9999 OR
      (p_payload->>'qcMaxDE100')::int NOT BETWEEN 0 AND 2000 OR
      (p_payload->>'toleranceBps')::int NOT BETWEEN 0 AND 1000 THEN
      RAISE EXCEPTION 'PAINT_INVALID_RECIPE_VALUES';
   END IF;
   FOR v_item IN SELECT value FROM jsonb_array_elements(p_payload->'pigments') LOOP
     v_sku:=v_item->>'sku';
     IF v_sku IS NULL OR v_sku !~ '^[A-Za-z0-9_-]{2,48}$' OR v_sku=ANY(v_seen) OR
        v_item->>'ulPerL' !~ '^[0-9]{1,6}$' THEN RAISE EXCEPTION 'PAINT_PIGMENT_INVALID'; END IF;
     v_value:=(v_item->>'ulPerL')::int;
     IF v_value NOT BETWEEN 1 AND 250000 THEN RAISE EXCEPTION 'PAINT_PIGMENT_RANGE'; END IF;
     v_seen:=array_append(v_seen,v_sku);
     v_sum:=v_sum+v_value;v_count:=v_count+1;
   END LOOP;
   IF v_sum>250000 OR v_count=0 THEN RAISE EXCEPTION 'PAINT_PIGMENT_TOTAL'; END IF;
   INSERT INTO c10_demo.paint_formula_v1(tenant_id,business_id,shade_code,formula_version,
     base_sku,output_sku,pigments,qc_max_de100,tolerance_bps,created_by)
   VALUES(v_tenant,p_business,p_payload->>'code',(p_payload->>'version')::int,
     p_payload->>'baseSku',p_payload->>'outputSku',p_payload->'pigments',
     (p_payload->>'qcMaxDE100')::int,(p_payload->>'toleranceBps')::int,v_actor)
   RETURNING id INTO v_id;
   v_result:=jsonb_build_object('formulaId',v_id,'version',(p_payload->>'version')::int,'status','REGISTERED');
   INSERT INTO c10_demo.paint_events_v1(tenant_id,business_id,formula_id,event,actor,request_key)
   VALUES(v_tenant,p_business,v_id,'FORMULA_CREATED',v_actor,p_request);
 ELSIF p_command='open' THEN
   IF p_payload->>'ticketKey' !~ '^[A-Za-z0-9_-]{2,48}$' OR
      p_payload->>'formulaId' !~ '^[0-9]{1,18}$' OR
      p_payload->>'baseML' !~ '^[0-9]{1,6}$' THEN RAISE EXCEPTION 'PAINT_INVALID_TICKET'; END IF;
   SELECT * INTO v_formula FROM c10_demo.paint_formula_v1
    WHERE id=(p_payload->>'formulaId')::bigint AND tenant_id=v_tenant AND business_id=p_business;
   IF NOT FOUND OR (p_payload->>'baseML')::int NOT BETWEEN 100 AND 200000 THEN
     RAISE EXCEPTION 'PAINT_FORMULA_OR_VOLUME_INVALID';
   END IF;
   INSERT INTO c10_demo.paint_tint_v1(tenant_id,business_id,ticket_key,formula_id,base_ml,created_by)
   VALUES(v_tenant,p_business,p_payload->>'ticketKey',v_formula.id,(p_payload->>'baseML')::int,v_actor)
   RETURNING id INTO v_id;
   v_result:=jsonb_build_object('ticketId',v_id,'ticketKey',p_payload->>'ticketKey','status','DRAFT','version',1);
   INSERT INTO c10_demo.paint_events_v1(tenant_id,business_id,ticket_id,event,actor,request_key)
   VALUES(v_tenant,p_business,v_id,'TICKET_OPENED',v_actor,p_request);
 ELSE
   IF p_payload->>'ticketId' !~ '^[0-9]{1,18}$' THEN RAISE EXCEPTION 'PAINT_INVALID_TICKET_ID'; END IF;
   SELECT * INTO v_ticket FROM c10_demo.paint_tint_v1
   WHERE id=(p_payload->>'ticketId')::bigint AND tenant_id=v_tenant AND business_id=p_business FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'PAINT_TICKET_NOT_IN_SCOPE'; END IF;
   SELECT * INTO v_formula FROM c10_demo.paint_formula_v1 WHERE id=v_ticket.formula_id;
   IF p_command='mix' THEN
     IF v_ticket.status NOT IN('DRAFT','QC_FAILED') OR
        jsonb_typeof(p_payload->'readings')<>'array' OR
        jsonb_array_length(p_payload->'readings')<>jsonb_array_length(v_formula.pigments)
     THEN RAISE EXCEPTION 'PAINT_MIX_STATE_OR_READINGS_INVALID'; END IF;
     v_seen:='{}'::text[];
     FOR v_item IN SELECT value FROM jsonb_array_elements(v_formula.pigments) LOOP
       v_sku:=v_item->>'sku';
       SELECT r.value INTO v_actual
         FROM jsonb_array_elements(p_payload->'readings') r(value) WHERE r.value->>'sku'=v_sku;
       IF v_actual IS NULL OR v_sku=ANY(v_seen) OR v_actual->>'actualUL' !~ '^[0-9]{1,8}$' THEN
         RAISE EXCEPTION 'PAINT_MISSING_OR_INVALID_READING'; END IF;
       v_seen:=array_append(v_seen,v_sku);
       v_expected:=round(((v_item->>'ulPerL')::numeric*v_ticket.base_ml)/1000,0);
       v_actual_ul:=(v_actual->>'actualUL')::int;
       IF abs(v_actual_ul-v_expected)*10000 >
          v_expected*v_formula.tolerance_bps THEN RAISE EXCEPTION 'PAINT_DOSE_OUT_OF_TOLERANCE'; END IF;
     END LOOP;
     IF (SELECT count(DISTINCT r.value->>'sku') FROM jsonb_array_elements(p_payload->'readings') r(value))
        <>jsonb_array_length(v_formula.pigments) THEN RAISE EXCEPTION 'PAINT_UNKNOWN_OR_DUPLICATE_PIGMENT'; END IF;
     UPDATE c10_demo.paint_tint_v1 SET status='MIXED',version=version+1,mixed_by=v_actor,
       mix_data=p_payload->'readings',qc_by=NULL,qc_delta_e100=NULL,qc_evidence_ref=NULL
      WHERE id=v_ticket.id RETURNING * INTO v_ticket;
     v_result:=jsonb_build_object('ticketId',v_ticket.id,'status',v_ticket.status,'version',v_ticket.version);
     INSERT INTO c10_demo.paint_events_v1(tenant_id,business_id,ticket_id,event,actor,request_key)
      VALUES(v_tenant,p_business,v_ticket.id,'MIX_RECORDED',v_actor,p_request);
   ELSE
     IF v_ticket.status<>'MIXED' OR v_actor=v_ticket.mixed_by OR
        p_payload->>'deltaE100' !~ '^[0-9]{1,5}$' OR
        p_payload->>'evidenceRef' !~ '^[A-Za-z0-9_-]{2,48}$' OR
        p_payload->>'method' !~ '^[A-Za-z0-9_-]{2,48}$' OR
        p_payload->>'instrumentRef' !~ '^[A-Za-z0-9_-]{2,48}$' OR
        p_payload->>'calibrated' IS DISTINCT FROM 'true' THEN
       RAISE EXCEPTION 'PAINT_QC_REVIEW_OR_EVIDENCE_INVALID';
     END IF;
     v_pass:=(p_payload->>'deltaE100')::int<=v_formula.qc_max_de100;
     UPDATE c10_demo.paint_tint_v1
       SET status=CASE WHEN v_pass THEN 'QC_PASSED' ELSE 'QC_FAILED' END,
         version=version+1,qc_by=v_actor,qc_delta_e100=(p_payload->>'deltaE100')::int,
         qc_evidence_ref=p_payload->>'evidenceRef',qc_method=p_payload->>'method',
         qc_instrument_ref=p_payload->>'instrumentRef'
       WHERE id=v_ticket.id RETURNING * INTO v_ticket;
     v_result:=jsonb_build_object('ticketId',v_ticket.id,'status',v_ticket.status,'version',v_ticket.version,
        'postAuthority',false);
     INSERT INTO c10_demo.paint_events_v1(tenant_id,business_id,ticket_id,event,actor,request_key,
       details) VALUES(v_tenant,p_business,v_ticket.id,'QC_RECORDED',v_actor,p_request,
       jsonb_build_object('passed',v_pass,'evidenceRef',v_ticket.qc_evidence_ref));
   END IF;
 END IF;
 UPDATE c10_demo.paint_receipt_v1 SET response=v_result WHERE id=v_receipt.id;
 RETURN v_result;
END $fn$;

CREATE OR REPLACE FUNCTION c10_demo.paint_report_v1(p_business bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE t bigint; draft_count int; mix_count int; failed_count int; pass_count int;
BEGIN
 SELECT tenant_id INTO t FROM c10_demo.businesses WHERE id=p_business;
 IF c10_demo.actor_uid() IS NULL OR t IS NULL OR NOT c10_demo.can_manage(t,p_business)
 THEN RAISE EXCEPTION 'PAINT_REPORT_SCOPE_DENIED'; END IF;
 SELECT count(*) FILTER (WHERE status='DRAFT'),
        count(*) FILTER (WHERE status='MIXED'),
        count(*) FILTER (WHERE status='QC_FAILED'),
        count(*) FILTER (WHERE status='QC_PASSED')
   INTO draft_count,mix_count,failed_count,pass_count
   FROM c10_demo.paint_tint_v1 WHERE tenant_id=t AND business_id=p_business;
 RETURN jsonb_build_object('businessId',p_business,'draft',draft_count,'mixed',mix_count,
   'qcFailed',failed_count,'qcPassed',pass_count,'stockPosted',false,'financePosted',false);
END $fn$;

REVOKE ALL ON FUNCTION c10_demo.paint_command_v1(bigint,text,jsonb,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION c10_demo.paint_report_v1(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION c10_demo.paint_command_v1(bigint,text,jsonb,text) TO authenticated;
GRANT EXECUTE ON FUNCTION c10_demo.paint_report_v1(bigint) TO authenticated;
