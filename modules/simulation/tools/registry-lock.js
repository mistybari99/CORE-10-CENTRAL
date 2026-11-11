"use strict";
/* Pins formulaHash of every registered model version. A formula/input change WITHOUT a new version fails CI.
   Usage: node modules/simulation/tools/registry-lock.js --write | --check */
const fs = require("fs"), path = require("path"); const E = require("../index.js"); const file = path.join(__dirname, "../data/registry-lock.json");
const lock = {}; for (const m of E.listModels()) lock[m.id + "@" + m.version] = { formulaHash: m.formulaHash, status: m.status };
const text = JSON.stringify(lock, Object.keys(lock).sort().reduce((a, k) => a.concat(k), []).concat(["formulaHash", "status"]), 1) + "\n";
const sorted = {}; Object.keys(lock).sort().forEach(k => (sorted[k] = lock[k])); const out = JSON.stringify(sorted, null, 1) + "\n";
if (process.argv.includes("--write")) { fs.writeFileSync(file, out); console.log("wrote", file); }
else { const cur = fs.existsSync(file) ? fs.readFileSync(file, "utf8") : ""; if (cur !== out) { console.error("REGISTRY LOCK DRIFT: a formula/input/status changed without a new model version"); process.exit(1); } console.log("registry lock OK (" + Object.keys(sorted).length + " model versions)"); }
