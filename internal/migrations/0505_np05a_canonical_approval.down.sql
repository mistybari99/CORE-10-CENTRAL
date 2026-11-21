DELETE FROM core10.control_rpc_map_v1 WHERE rpc_name IN
 ('mfg_submit_approval_v1','mfg_approve_recipe_with_approval_v1','mfg_release_batch_with_approval_v1');
DROP FUNCTION core10.mfg_release_batch_with_approval_v1(bigint,bigint,bigint,bigint,text);
DROP FUNCTION core10.mfg_approve_recipe_with_approval_v1(bigint,bigint,bigint,timestamptz,bigint,text);
DROP FUNCTION core10._mfg_completed_approval_v1(bigint,bigint,bigint,bigint,text,bigint,timestamptz);
DROP FUNCTION core10.mfg_submit_approval_v1(bigint,bigint,text,bigint,timestamptz,text);
DROP FUNCTION core10.mfg_approval_packet_v1(bigint,bigint,text,bigint,timestamptz);
