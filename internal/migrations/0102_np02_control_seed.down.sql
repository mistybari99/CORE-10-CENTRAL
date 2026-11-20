-- Rollback of 0102. Refuses while any Owner setting or exception refers to the catalog.
DO $$
BEGIN
 IF EXISTS (SELECT 1 FROM core10.control_setting_versions_v1)
    OR EXISTS (SELECT 1 FROM core10.control_overrides_v1) THEN
  RAISE EXCEPTION 'CONTROL_HISTORY_NOT_EMPTY: Owner setting history is never dropped by rollback';
 END IF;
END $$;
DELETE FROM core10.control_rpc_map_v1;
DELETE FROM core10.control_catalog_v1 WHERE feature_key IN
 ('audit.immutability','tenant.isolation','access.expiry_revocation','gov002.approval_policy',
  'gov002.review','gov003.review_export','setup001.profile_preview','setup001.provision','inventory.stock_event');
