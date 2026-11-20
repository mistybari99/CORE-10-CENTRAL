-- Rollback of 0106: the two review RPCs return to pending (their bindings are re-proven on re-apply).
UPDATE core10.control_rpc_map_v1
 SET status = 'pending', test_ref = NULL, reason = 'Binding to the Control port was rolled back; to be re-proven'
 WHERE rpc_name IN ('decide_approval', 'withdraw_typed_approval_v1') AND status = 'enforced';
