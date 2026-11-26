\set ON_ERROR_STOP on
-- PACK-02 S3: control placement projection under SYNTHETIC claims (not GoTrue).
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS
 $$ SELECT set_config('request.jwt.claim.sub',COALESCE(p::text,''),false) $$;
CREATE FUNCTION pg_temp.expect(p_sql text,p_code text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 EXECUTE p_sql;
 RAISE EXCEPTION 'EXPECTED % BUT SUCCEEDED: %',p_code,p_sql;
EXCEPTION WHEN OTHERS THEN
 IF SQLERRM LIKE 'EXPECTED %' THEN RAISE; END IF;
 IF SQLERRM<>p_code THEN RAISE EXCEPTION 'EXPECTED % GOT % FOR %',p_code,SQLERRM,p_sql; END IF;
END $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO authenticated;
CREATE FUNCTION pg_temp.item(p jsonb,p_id text) RETURNS jsonb LANGUAGE sql AS
 $$ SELECT i FROM jsonb_array_elements(p->'items') i WHERE i->>'control_id'=p_id $$;
SET ROLE authenticated;

-- Tenant owner configures four placements through the canonical A044 writer.
SELECT pg_temp.as_user('11111111-1111-4111-8111-111111111111');
DO $t$ DECLARE c jsonb; b jsonb; BEGIN
 PERFORM core10.write_control_setting_v1(101,'inventory.count','both','business_owner',true,0,'p2c_both_0001','PACK-02 placement both');
 PERFORM core10.write_control_setting_v1(101,'sales.orders','business_only','request_approval',false,0,'p2c_bizonly_01','PACK-02 placement business only');
 PERFORM core10.write_control_setting_v1(101,'finance.payments','hidden_from_menus','central_only',false,0,'p2c_hidden_001','PACK-02 placement hidden');
 PERFORM core10.write_control_setting_v1(101,'data.export','central_only','central_only',false,0,'p2c_central_01','PACK-02 placement central');
 c:=core10.pack02_controls_v1('central',101);
 IF jsonb_array_length(c->'items')<>18 THEN RAISE EXCEPTION 'central registry must list all controls'; END IF;
 IF pg_temp.item(c,'inventory.count')->>'in_menu'<>'true' OR pg_temp.item(c,'data.export')->>'in_menu'<>'true'
  OR pg_temp.item(c,'sales.orders')->>'in_menu'<>'false' OR pg_temp.item(c,'finance.payments')->>'in_menu'<>'false'
  OR pg_temp.item(c,'ui.favorites')->>'in_menu'<>'true' THEN RAISE EXCEPTION 'central menu flags %',c; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(c->'items') i WHERE i->>'edit'<>'direct') THEN RAISE EXCEPTION 'central edit'; END IF;
 -- Tenant owner on the business surface sees only that business menu, edits directly.
 b:=core10.pack02_controls_v1('business',101);
 IF jsonb_array_length(b->'items')<>2 OR pg_temp.item(b,'sales.orders')->>'edit'<>'direct' THEN RAISE EXCEPTION 'owner business surface %',b; END IF;
 -- Unconfigured sister business: nothing projected locally; settings never bleed across businesses.
 IF jsonb_array_length(core10.pack02_controls_v1('business',102)->'items')<>0 THEN RAISE EXCEPTION 'sister business inherited placement'; END IF;
 IF c->>'placement_is_not_permission'<>'true' OR c->>'production_certified'<>'false' THEN RAISE EXCEPTION 'truth flags'; END IF;
 PERFORM pg_temp.expect($$SELECT core10.pack02_controls_v1('central',201)$$,'PACK02_CONTROLS_DENIED');
 PERFORM pg_temp.expect($$SELECT core10.pack02_controls_v1('staff',101)$$,'PACK02_SURFACE_INVALID');
 PERFORM pg_temp.expect($$SELECT core10.pack02_controls_v1(NULL,101)$$,'PACK02_SURFACE_INVALID');
 PERFORM pg_temp.expect($$SELECT core10.pack02_controls_v1('business',999999)$$,'PACK02_CONTROLS_DENIED');
END $t$;

-- Delegated business owner: only Business Only/Both; hidden + central-only undisclosed.
SELECT pg_temp.as_user('22222222-2222-4222-8222-222222222222');
DO $t$ DECLARE b jsonb; BEGIN
 b:=core10.pack02_controls_v1('business',101);
 IF jsonb_array_length(b->'items')<>2 THEN RAISE EXCEPTION 'business menu size %',b; END IF;
 IF pg_temp.item(b,'inventory.count')->>'edit'<>'direct' OR pg_temp.item(b,'sales.orders')->>'edit'<>'request' THEN RAISE EXCEPTION 'delegated edit modes %',b; END IF;
 IF b::text LIKE '%finance.payments%' OR b::text LIKE '%data.export%' OR b ? 'tenant_id' THEN RAISE EXCEPTION 'hidden/central control disclosed'; END IF;
 PERFORM pg_temp.expect($$SELECT core10.pack02_controls_v1('central',101)$$,'PACK02_CONTROLS_DENIED');
 PERFORM pg_temp.expect($$SELECT core10.pack02_controls_v1('business',102)$$,'PACK02_CONTROLS_DENIED');
END $t$;

-- Manager, staff, investor, inactive, other tenant, operator, anonymous: no control surface.
SELECT pg_temp.as_user('33333333-3333-4333-8333-333333333333');
SELECT pg_temp.expect($$SELECT core10.pack02_controls_v1('business',101)$$,'PACK02_CONTROLS_DENIED');
SELECT pg_temp.as_user('44444444-4444-4444-8444-444444444444');
SELECT pg_temp.expect($$SELECT core10.pack02_controls_v1('business',101)$$,'PACK02_CONTROLS_DENIED');
SELECT pg_temp.expect($$SELECT core10.pack02_controls_v1('central',101)$$,'PACK02_CONTROLS_DENIED');
SELECT pg_temp.as_user('55555555-5555-4555-8555-555555555555');
SELECT pg_temp.expect($$SELECT core10.pack02_controls_v1('business',101)$$,'PACK02_CONTROLS_DENIED');
SELECT pg_temp.as_user('66666666-6666-4666-8666-666666666666');
SELECT pg_temp.expect($$SELECT core10.pack02_controls_v1('business',101)$$,'PACK02_CONTROLS_DENIED');
SELECT pg_temp.as_user('77777777-7777-4777-8777-777777777777');
SELECT pg_temp.expect($$SELECT core10.pack02_controls_v1('central',101)$$,'PACK02_CONTROLS_DENIED');
SELECT pg_temp.expect($$SELECT core10.pack02_controls_v1('business',101)$$,'PACK02_CONTROLS_DENIED');
SELECT pg_temp.as_user('99999999-9999-4999-8999-999999999999');
SELECT pg_temp.expect($$SELECT core10.pack02_controls_v1('central',101)$$,'PACK02_CONTROLS_DENIED');
SELECT pg_temp.as_user(NULL);
SELECT pg_temp.expect($$SELECT core10.pack02_controls_v1('business',101)$$,'PACK02_SIGNED_SESSION_REQUIRED');
-- Staff workspace projection still carries no control data at all.
SELECT pg_temp.as_user('44444444-4444-4444-8444-444444444444');
DO $t$ BEGIN
 IF core10.pack02_workspace_v1('staff',101)::text ~ 'control|placement|finance\.' THEN RAISE EXCEPTION 'staff workspace leaks controls'; END IF;
END $t$;
RESET ROLE;
-- Projection wrote nothing: exactly the four A044 settings exist.
DO $t$ BEGIN
 IF (SELECT count(*) FROM core10.control_settings_v1)<>4 THEN RAISE EXCEPTION 'projection wrote settings'; END IF;
END $t$;
SELECT 'PASS PACK-02 controls-e2e' AS result;
