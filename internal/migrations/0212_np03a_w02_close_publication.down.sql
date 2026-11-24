DO $w02$
BEGIN
 IF EXISTS (SELECT 1 FROM core10.w02_close_publications_v1)
 THEN RAISE EXCEPTION 'W02_PUBLICATION_ROLLBACK_REQUIRES_EVIDENCE_RETENTION'; END IF;
END $w02$;
DROP FUNCTION core10._w02_publish_verified_close_v1(bigint,bigint,bigint,text,jsonb,jsonb);
DROP FUNCTION core10._w02_close_receipt_v1(core10.w02_close_publications_v1,text,boolean);
DROP TABLE core10.w02_close_publications_v1;
