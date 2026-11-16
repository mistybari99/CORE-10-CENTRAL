-- Committed fixtures only in a dedicated local/CI browser-test database.
\set ON_ERROR_STOP on
\ir fixtures.sql
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
SELECT core10.control_set_v1(101,NULL,'sales.order_draft',true,0::smallint,'{"max_discount_percent":5}',NULL,false,0,'Synthetic browser order fixture','ui_enable_draft');
SELECT core10.control_set_v1(101,NULL,'sales.order_transition',true,0::smallint,'{}',NULL,false,0,'Synthetic browser order fixture','ui_enable_transition');
