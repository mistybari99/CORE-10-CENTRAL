-- Rollback of 0105: remove the label keys only.
UPDATE core10.control_catalog_v1 c SET params = (
 SELECT coalesce(jsonb_object_agg(k, v - 'label_bn' - 'label_en'), '{}'::jsonb) FROM jsonb_each(c.params) e(k, v));
