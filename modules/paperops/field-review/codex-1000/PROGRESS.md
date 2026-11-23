# Codex original-source audit

A001 covers 50 ordered R-01 IDs from board_recon through exp_amt. The report has grouped rule evidence, synthetic fixtures and 12 open findings (10 high and 2 medium). See batch-A001.json and issues.json.

Run 45112442555 passed all 143 inherited PaperOps tests. CI stages the byte-identical frozen form at the path used by historical tests. The canonical guard ran against the audit checkout and failed on an inherited legacy loader in core10-asset-maintenance-assets.html. This requires a parent-lane correction.

The new warning test was corrected to accept an exact warning invocation within a larger verified source excerpt. Exact-head CI rerun pending.

A001 remains open. A002–A020 are queued in manifest order. Coordination Board and Decision Book: NOT WRITTEN.
