-- S1-b 0004 rollback; fail safely if dependent business rows exist.
DROP VIEW core10.business_setup_overview_v1;
DROP FUNCTION core10.setup_business_v1(bigint,text,text,text,text,jsonb,text,text);
DROP POLICY business_config_scope_v1 ON core10.business_configuration_v1;
DROP POLICY business_modules_scope_v1 ON core10.business_module_settings_v1;
DROP POLICY setup_runs_owner_v1 ON core10.business_setup_runs_v1;
DROP POLICY template_module_catalog_v1 ON core10.template_modules_v1;
DROP TABLE core10.business_setup_runs_v1;
DROP TABLE core10.business_module_settings_v1;
DROP TABLE core10.business_configuration_v1;
DROP TABLE core10.template_modules_v1;
DELETE FROM core10.templates WHERE code='sweets_bakery';
