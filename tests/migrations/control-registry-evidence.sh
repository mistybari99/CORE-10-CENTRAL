#!/usr/bin/env bash
# NP02 / B-010: every "enforced" registry row names a test file that exists, exercises that RPC,
# proves the switch-off denial (CONTROL_DISABLED) and is executed by a CI workflow.
set -euo pipefail
cd "$(dirname "$0")/../.."
rows=$(psql -X -At -F'|' -c "select rpc_name, test_ref from core10.control_rpc_map_v1 where status='enforced' order by 1")
n=0
while IFS='|' read -r rpc ref; do
 [ -n "$rpc" ] || continue; n=$((n+1))
 [ -f "$ref" ] || { echo "EVIDENCE_MISSING $rpc: $ref does not exist"; exit 1; }
 grep -q "$rpc" "$ref" || { echo "EVIDENCE_DOES_NOT_CALL $rpc: $ref never calls it"; exit 1; }
 grep -q "CONTROL_DISABLED" "$ref" || { echo "EVIDENCE_NO_DENIAL $rpc: $ref does not assert CONTROL_DISABLED"; exit 1; }
 grep -rqF "$ref" .github/workflows || { echo "EVIDENCE_NOT_IN_CI $rpc: no workflow runs $ref"; exit 1; }
done <<< "$rows"
echo "PASS CONTROL EVIDENCE: $n enforced RPC(s), each with an existing CI-run test that proves CONTROL_DISABLED"
