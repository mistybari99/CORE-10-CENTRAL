-- NP02 / B-010 / 0102: initial Control catalog and the RPC registry (DEC-08).
-- Later packs add their own features in their own migration block with plain INSERTs here;
-- a feature without a catalog row cannot be controlled and so is not finished.

INSERT INTO core10.control_catalog_v1(feature_key,title_en,title_bn,pack,invariant,default_enabled,
 default_stages,max_stages,allow_site_scope,approval_domain,approval_action,params) VALUES
 ('audit.immutability','Audit and approval history cannot be altered','অডিট ও অনুমোদনের ইতিহাস বদলানো যায় না','NP01',true,true,0,0,false,NULL,NULL,'{}'),
 ('tenant.isolation','Each tenant sees only its own data','প্রতিটি প্রতিষ্ঠান শুধু নিজের তথ্য দেখে','NP01',true,true,0,0,false,NULL,NULL,'{}'),
 ('access.expiry_revocation','Expired or revoked access stops at once','মেয়াদ শেষ বা বাতিল অনুমতি সঙ্গে সঙ্গে বন্ধ','NP01',true,true,0,0,false,NULL,NULL,'{}'),
 ('gov002.approval_policy','Publish approval policies','অনুমোদন নীতি প্রকাশ','NP01',false,true,0,0,true,NULL,NULL,
  '{"ttl_minutes":{"type":"int","min":5,"max":43200,"default":1440}}'),
 ('gov002.review','Routed review of approval requests','অনুমোদন আবেদনের ধাপে ধাপে পর্যালোচনা','NP01',false,true,1,5,true,NULL,NULL,
  '{"exception_escalation":{"type":"bool","default":true}}'),
 ('gov003.review_export','Audit readiness, risk review and export','অডিট প্রস্তুতি, ঝুঁকি পর্যালোচনা ও রপ্তানি','NP01',false,false,0,5,true,NULL,NULL,
  '{"max_rows":{"type":"int","min":1,"max":10000,"default":1000},"metadata_only":{"type":"bool","default":true}}'),
 ('setup001.profile_preview','Preview a business setup profile','ব্যবসার সেটআপ প্রোফাইল প্রিভিউ','NP01',false,true,0,0,false,NULL,NULL,'{}'),
 ('setup001.provision','Create and activate a business or site','ব্যবসা বা সাইট তৈরি ও চালু','NP01',false,true,0,5,false,NULL,NULL,
  '{"max_sites":{"type":"int","min":1,"max":1000,"default":50}}'),
 ('inventory.stock_event','Post stock events','স্টক ইভেন্ট পোস্ট','NP03A',false,true,0,5,true,'inventory','adjust',
  '{"allow_negative_stock":{"type":"bool","default":false},"max_adjust_qty":{"type":"numeric","min":0,"max":1000000,"default":1000}}');

INSERT INTO core10.control_rpc_map_v1(rpc_name,status,feature_key,reason,lane,board_row) VALUES
 ('build01_set_access_v1','exempt',NULL,'Auth-port administration: grants and revokes access; Owner authority checked by can_manage and audited','ChatGPT','B-004'),
 ('change_access_v1','exempt',NULL,'Auth-port administration: changes access; Owner authority checked and audited','ChatGPT','B-004'),
 ('build02a_set_approval_policy_v1','exempt',NULL,'Auth-port administration: sets which roles may use approval actions','ChatGPT','B-004'),
 ('control_set_v1','exempt',NULL,'Control-port self-administration: Owner only, versioned and audited; cannot change invariants','Claude','B-010'),
 ('control_revert_v1','exempt',NULL,'Control-port self-administration: Owner only, restores an earlier version as a new version','Claude','B-010'),
 ('control_grant_override_v1','exempt',NULL,'Control-port self-administration: Owner grants a one-time audited exception','Claude','B-010'),
 ('control_revoke_override_v1','exempt',NULL,'Control-port self-administration: Owner withdraws an unused exception','Claude','B-010'),
 ('build01_setup_v1','pending','setup001.provision','Setup is not yet bound to the provision control; to be connected by the NP01 lane','ChatGPT','B-008'),
 ('build01_site_v1','pending','setup001.provision','Site creation is not yet bound to the provision control','ChatGPT','B-008'),
 ('setup_business_v1','pending','setup001.provision','Business setup is not yet bound to the provision control','ChatGPT','B-008'),
 ('setup_industry_draft_v2','pending','setup001.provision','Industry draft setup is not yet bound to the provision control','ChatGPT','B-008'),
 ('provision_business','pending','setup001.provision','A018 fixture provisioning, superseded by build01_setup_v1; retire with the legacy installer','Claude','B-009'),
 ('provision_site','pending','setup001.provision','A018 fixture provisioning, superseded by build01_site_v1; retire with the legacy installer','Claude','B-009'),
 ('post_stock_event','pending','inventory.stock_event','Stock posting is not yet bound to its control; connects with the inventory command ledger','Claude','B-012'),
 ('publish_approval_policy_v1','pending','gov002.approval_policy','Policy publishing is not yet bound to its control','ChatGPT','B-006'),
 ('configure_approval_route_v1','pending','gov002.review','Route configuration is not yet bound to the review control','ChatGPT','B-006'),
 ('submit_typed_approval_v1','pending','gov002.review','Submission is not yet bound to the review control or its stage count','ChatGPT','B-006'),
 ('decide_approval','pending','gov002.review','Decisions are not yet bound to the review control','ChatGPT','B-006'),
 ('delegate_approval_stage_v1','pending','gov002.review','Delegation is not yet bound to the review control','ChatGPT','B-006'),
 ('revoke_approval_delegation_v1','pending','gov002.review','Delegation revoke is not yet bound to the review control','ChatGPT','B-006'),
 ('withdraw_typed_approval_v1','pending','gov002.review','Withdrawal is not yet bound to the review control','ChatGPT','B-006');
