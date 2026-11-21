-- TEST ONLY, loaded inside a rolled-back disposable test transaction.
-- Not canonical item/UOM validation or an approved production replacement equivalence.
CREATE OR REPLACE FUNCTION core10._mfg_substitution_check_v1(p_recipe bigint) RETURNS void
LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM core10.bom_substitution_rules_v1 WHERE bom_id=p_recipe AND
  (business_id<>9511 OR alternative_item_id NOT IN(9546,9547) OR uom_ref NOT IN('fixture:kg','fixture:piece')))
 THEN RAISE EXCEPTION 'NOT_CONNECTED:FIXTURE_SUBSTITUTION'; END IF;
END $$;
