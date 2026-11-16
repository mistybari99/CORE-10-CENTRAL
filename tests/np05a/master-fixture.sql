-- TEST-ONLY adapter replacement: no hosted Auth and no real Master UOM verification.
-- Deliberately limited to the fictional recipe UOMs. Executed ONLY in disposable QA databases.
CREATE OR REPLACE FUNCTION core10._mfg_master_check_v1(p_recipe bigint) RETURNS void
LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM core10.bom_recipes_v1 WHERE id=p_recipe AND business_id=9511 AND yield_uom_ref='fixture:piece')
 OR EXISTS(SELECT 1 FROM core10.bom_ingredients_v1 WHERE bom_id=p_recipe AND uom_ref NOT IN('fixture:kg','fixture:piece'))
 THEN RAISE EXCEPTION 'NOT_CONNECTED:FIXTURE_UOM'; END IF;
END $$;
