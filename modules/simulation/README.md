# modules/simulation — C10-A025 Simulation Engine (DRAFT · isolated · advisory-only)

Not wired into any live ERP screen. Synthetic data only. See `docs/development/C10_A025_SIMULATION_TECHNICAL_HANDOVER.md` (run/test/integrate), `…_DECISION_LOG.md`, `…_MODEL_COVERAGE.md` (generated), `…_EXTENSION_GUIDE.md`.

```bash
node tests/c10_a025/run-all.js        # all gates
PORT=8099 node tests/e2e/static_server.js   # → /modules/simulation/ui/lab.html and quick.html
```
Never: apply to live, use real customer data, point at production Supabase, or merge before the Owner-gated release decision.
