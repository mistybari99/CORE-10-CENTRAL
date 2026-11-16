-- NP02 / B-021 / 0105: bilingual labels for the seeded control parameters (descriptor keys label_bn, label_en).
-- Descriptor validation ignores extra keys, so existing settings stay valid.
UPDATE core10.control_catalog_v1 SET params = params
 || jsonb_build_object('ttl_minutes', params->'ttl_minutes' || '{"label_bn":"অনুমোদনের মেয়াদ (মিনিট)","label_en":"Approval validity (minutes)"}')
 WHERE feature_key = 'gov002.approval_policy';
UPDATE core10.control_catalog_v1 SET params = params
 || jsonb_build_object('exception_escalation', params->'exception_escalation' || '{"label_bn":"ব্যতিক্রম ঊর্ধ্বতনের কাছে পাঠানো","label_en":"Escalate exceptions"}')
 WHERE feature_key = 'gov002.review';
UPDATE core10.control_catalog_v1 SET params = params
 || jsonb_build_object('max_rows', params->'max_rows' || '{"label_bn":"সর্বোচ্চ সারি","label_en":"Maximum rows"}',
                       'metadata_only', params->'metadata_only' || '{"label_bn":"শুধু মেটাডেটা","label_en":"Metadata only"}')
 WHERE feature_key = 'gov003.review_export';
UPDATE core10.control_catalog_v1 SET params = params
 || jsonb_build_object('max_sites', params->'max_sites' || '{"label_bn":"সর্বোচ্চ সাইট","label_en":"Maximum sites"}')
 WHERE feature_key = 'setup001.provision';
UPDATE core10.control_catalog_v1 SET params = params
 || jsonb_build_object('allow_negative_stock', params->'allow_negative_stock' || '{"label_bn":"ঋণাত্মক স্টক অনুমতি","label_en":"Allow negative stock"}',
                       'max_adjust_qty', params->'max_adjust_qty' || '{"label_bn":"সর্বোচ্চ সমন্বয় পরিমাণ","label_en":"Maximum adjustment quantity"}')
 WHERE feature_key = 'inventory.stock_event';
