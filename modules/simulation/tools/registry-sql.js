"use strict";
/* Emits INSERT statements publishing every registered model version into c10_sim.model_registry (immutable once published). */
const E = require("../index.js"); const q = s => "$q$" + String(s).replace(/\$q\$/g, "") + "$q$"; const rows = [];
for (const m of E.listModels()) rows.push("(" + [q(m.id), q(m.version), q(m.status), m.formulaHash ? q(m.formulaHash) : "null", q(JSON.stringify({ family: m.family, title: m.title, reason: m.reason || null }))].join(",") + "::jsonb" .replace("::jsonb", "") + ")");
console.log("insert into c10_sim.model_registry(model_id, version, status, formula_hash, spec) values\n" + E.listModels().map(m => "(" + [q(m.id), q(m.version), q(m.status), m.formulaHash ? q(m.formulaHash) : "null", q(JSON.stringify({ family: m.family, title: m.title, reason: m.reason || null })) + "::jsonb"].join(",") + ")").join(",\n") + "\non conflict do nothing;");
