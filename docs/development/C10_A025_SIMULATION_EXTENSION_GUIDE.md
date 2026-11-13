# C10-A025 Simulation — Extension Guide (add a model / version without breaking history)

## Rules that never bend
1. A published `id@version` is **immutable**. Change a formula ⇒ new version. CI (`registry-lock.js --check`) fails otherwise.
2. Saved scenarios stay pinned to their version. Adoption of a new version is explicit (`clone` with `modelVersion`, or `compareModelVersions`).
3. No `eval`, no `Function`, no SQL expression strings, no floats for money, no clock/random inside `lib/` or `models/` (guard test).
4. A model is `implemented_tested` only with **≥2 goldens incl. ≥1 adverse**, negative tests, and bilingual R128 text. Otherwise register `partial`, `research_only` or `not_implemented` with a `reason`.

## Add a new model family (example `M21`)
1. Create `modules/simulation/models/<yours>.js`; `require("./spec")` helpers (`money`, `pct`, `list`, …). Inputs carry `l:[English, বাংলা]`.
2. Call `registerModel({ id, version:"1.0.0", family, title:{en,bn}, explain:{what,when,why,example}:{en,bn}, industries, inputs, outputs, formulaText, assumptions, limitations, status, calculate(v, ctx) })`. `calculate` receives parsed `Dec`/arrays and returns `{outputs, warnings, feasibility, breakdown}`. Use `Dec` only. Return `null` for unknowns.
3. `require` the file in `modules/simulation/index.js` (before `not_built.js`).
4. Add fixtures to `tests/c10_a025/golden_reference.py` (`add(...)` + an independent `mXX()` implementation with `Fraction`). Run `python3 tests/c10_a025/golden_reference.py --write`. The reference must **not** share code with the JS model.
5. `node modules/simulation/tools/registry-lock.js --write`, `node modules/simulation/tools/build-bundle.js`, `node modules/simulation/tools/gen-coverage-doc.js`; commit all generated files.
6. Add the family to `lib/coverage.js` if it maps to a U/R item, and negative tests to `tests/c10_a025/models.test.js`.
7. If SQL persistence must know it: the registry SQL is generated (`tools/registry-sql.js`), published rows are immutable.

## New **version** of an existing model
Register `version:"2.0.0"` next to `1.0.0` (see M01). Keep v1 untouched. Add goldens for v2, keep v1 goldens. Prove `v2(default inputs) == v1` where the change is additive (see `registry.test.js`). Retire v1 only with `retired:true`; retired versions run only with `ctx.allowRetired` (for reproduction).

## New industry pack / template
Packs are data: add the industry id to a model's `industries`. Declarative owner formulas use **M20** (typed expressions: `+ − * / ( )`, `min max abs pos round2`; ≤200 nodes, depth ≤20). Do not add per-industry calculators.

## New Quick Simulation context
Add `{ contextKey: { modelId, label:[en,bn] } }` to `lib/quick.js`; add a parity case in `tests/c10_a025/parity.test.js`. Quick must keep calling `runModel` — never a second formula path.

## Feature toggle / rollout
There is intentionally **no** runtime flag that enables apply-to-live or live navigation. Any future activation is a separate Owner-gated change that attaches authorised canonical domain commands, not a toggle in this module.
