#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
psql -X -q -v ON_ERROR_STOP=1 -f /tmp/np05a-canonical-hooks.sql
psql -X -q -v ON_ERROR_STOP=1 -f tests/np05a/canonical-master-seed.sql
