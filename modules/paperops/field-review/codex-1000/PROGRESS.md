# Codex original-source audit

A001 covers the first 50 ordered R-01 IDs from board_recon through exp_amt. It has 12 open findings (10 high and 2 medium), grouped source evidence and synthetic fixtures. See batch-A001.json and issues.json.

The initial Node 22 audit job passed 21 tests. The initial full suite passed 140 tests and failed 3 because this parent tracks the frozen source at root. The workflow now stages the original blob under the path expected by inherited tests and runs the hash-pinned canonical guard against the audit checkout. Both are temporary checkout operations. Exact-head rerun pending.

A001 gate remains pending until CI passes. A002–A020 remain queued in manifest order. Coordination Board and Decision Book: NOT WRITTEN.
