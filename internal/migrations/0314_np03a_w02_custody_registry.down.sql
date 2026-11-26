-- Refuse rollback of any populated registry instead of discarding approved source evidence.
DO $w02$
BEGIN
 IF EXISTS (SELECT 1 FROM core10.w02_pairs_v1)
 THEN RAISE EXCEPTION 'W02_REGISTRY_ROLLBACK_REQUIRES_EVIDENCE_RETENTION'; END IF;
END $w02$;
DROP FUNCTION core10.w02_custody_snapshot_v1(bigint,bigint,bigint);
DROP TABLE core10.w02_challan_lines_v1,core10.w02_close_transfers_v1,core10.w02_closes_v1,
 core10.w02_key_revocations_v1,core10.w02_keys_v1,core10.w02_pairs_v1;
DROP FUNCTION core10._w02_check_transfer_scope_v1(),core10._w02_immutable_v1(),core10._w02_stamp_close_v1();
DROP INDEX core10.w02_posted_command_reads_v1,core10.w02_posting_transfer_reads_v1,core10.w02_transfer_pair_reads_v1;
