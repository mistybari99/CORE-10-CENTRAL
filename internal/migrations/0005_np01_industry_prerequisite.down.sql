-- S1-b 0005 rollback. No CASCADE; reject when business references a template.
DROP FUNCTION core10.setup_industry_draft_v2(bigint,text,text,text,text,jsonb,jsonb,text,text);
DROP POLICY industry_module_catalog_authenticated_v2 ON core10.industry_module_catalog_v2;
DROP POLICY industry_catalog_authenticated_v2 ON core10.industry_catalog_v2;
DROP TABLE core10.industry_module_catalog_v2;
DROP TABLE core10.industry_catalog_v2;
DELETE FROM core10.templates WHERE code IN ('restaurant','paint_hardware','retail_wholesale','general_manufacturing','construction','import_export','ecommerce','technology_digital','services');
