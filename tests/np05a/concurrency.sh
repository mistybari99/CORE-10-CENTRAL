#!/usr/bin/env bash
# Two real sessions, same and competing command keys; no production port mocks.
set -euo pipefail
cd "$(dirname "$0")/../.."
psql -X -q -v ON_ERROR_STOP=1 -f tests/np05a/race-seed.sql >/dev/null
batch=$(psql -X -At -c "select id from core10.production_batches_v1 where business_id=9511")
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
claim="select set_config('request.jwt.claims','{\"sub\":\"95222222-2222-4222-8222-222222222222\"}',false); SET ROLE authenticated;"
output="'{\"good\":95,\"rejected\":2,\"rework\":1,\"loss\":2,\"reason\":\"PROCESS_LOSS\",\"lot_ref\":\"FICTIONAL-RACE\",\"consumption\":[{\"line\":1,\"qty\":10,\"lot_ref\":\"FICTIONAL-MILK\"}]}'::jsonb"
# Hold the batch row in session A while B waits. Same key must return the original receipt.
psql -X -q -v ON_ERROR_STOP=1 -c "BEGIN; $claim SELECT core10.mfg_record_output_v1(9511,9521,$batch,$output,'race_record_01'); SELECT pg_sleep(1); COMMIT;" >"$work/a" 2>&1 & a=$!
psql -X -q -v ON_ERROR_STOP=1 -c "$claim SELECT core10.mfg_record_output_v1(9511,9521,$batch,$output,'race_record_01');" >"$work/b" 2>&1 & b=$!
wait "$a"; wait "$b"
[ "$(psql -X -At -c "select count(*) from core10.mfg_command_receipts_v1 where request_key='race_record_01'")" = 1 ]
[ "$(psql -X -At -c "select count(*) from core10.canonical_audit_events_v1 where source_domain='manufacturing' and action='mfg.output_record'")" = 1 ]
# A different key cannot record already-recorded output or invent another event.
if psql -X -q -v ON_ERROR_STOP=1 -c "$claim SELECT core10.mfg_record_output_v1(9511,9521,$batch,$output,'race_record_02');" >"$work/c" 2>&1; then echo 'DOUBLE_RECORD_ACCEPTED'; exit 1; fi
grep -q MFG_BATCH_STATE "$work/c"
[ "$(psql -X -At -c 'select count(*) from core10.stock_movements where business_id=9511')" = 0 ]
# Rollback refuses to erase domain/control history, preserving all source/audit links.
if psql -X -q -v ON_ERROR_STOP=1 -1 -f internal/migrations/0500_np05a_manufacturing.down.sql >"$work/down" 2>&1; then echo 'DESTRUCTIVE_ROLLBACK_ACCEPTED'; exit 1; fi
grep -q MFG_ROLLBACK_HAS_HISTORY "$work/down"
echo NP05A_CONCURRENT_REPLAY_AND_SAFE_ROLLBACK_OK
