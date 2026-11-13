#!/usr/bin/env node
// CORE 10 CENTRAL: deterministic future-UI language contract gate.
// Existing legacy UI remains outside new-file enforcement until scoped migration.
import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { SUPPORTED_LOCALES, DEFAULT_LOCALE, CATALOG, NAMED_CATALOG } from "../preview/i18n.mjs";

const modes = ["bn-BD", "bn-BD-mixed", "en"];
assert.deepEqual(SUPPORTED_LOCALES, modes, "Every UI must preserve Bengali / Eng-Bng / English");
assert.equal(DEFAULT_LOCALE, "bn-BD", "Owner default is natural Bengali");
assert.ok(CATALOG.length >= 200, "Preserve reviewed existing phrase coverage");
for (const [key, ...copy] of CATALOG) {
  assert.equal(copy.length, 2, "Every phrase needs Bengali and Eng/Bng: " + key);
  assert.ok(key && copy.every(s => typeof s === "string" && s.trim()), "Missing copy for " + key);
}
for (const [key, values] of Object.entries(NAMED_CATALOG)) {
  assert.match(key, /^[a-z]+\.[a-zA-Z][\w]*$/);
  assert.equal(values.length, 3, "Every named key needs all 3 locales: " + key);
  assert.ok(values.every(x => typeof x === "string" && x.trim()), "Missing named translation: " + key);
}
const ag = readFileSync("AGENTS.md", "utf8");
const policy = readFileSync("docs/ux/C10_LANGUAGE_CONTRACT.md", "utf8");
const glossary = readFileSync("docs/ux/C10_BN_FIRST_GLOSSARY.md", "utf8");
for (const [name, text] of [["AGENTS", ag], ["contract", policy], ["glossary", glossary]]) {
  for (const label of ["Bengali", "Eng/Bng", "English"]) {
    assert.ok(text.includes(label), name + " does not explain " + label);
  }
}
assert.ok(ag.includes("C10_LANGUAGE_CONTRACT.md"), "All agents must read language policy");
for (const sample of ["স্টকের হিসাব মিলিয়ে নিন", "Stock-এর হিসাব মিলিয়ে নিন"]) {
  assert.ok(policy.includes(sample), "Owner example missing: " + sample);
}
for (const path of ["preview/worker.mjs", "preview/build01-build02a.mjs"]) {
  const src = readFileSync(path, "utf8");
  assert.ok(src.includes('value=\\\"bn-BD-mixed\\\"') || src.includes('value="bn-BD-mixed"'), "Missing Eng/Bng selector " + path);
  for (const label of ["Bengali", "Eng/Bng", "English"]) assert.ok(src.includes(label), "Missing option " + label + " in " + path);
}

// Enforce a translation adapter marker for *new* frontend screens. Existing
// HTML from before this contract is grandfathered, NOT certified translated.
const base = (process.env.BASE_SHA ?? "").trim();
if (base) {
  const names = execFileSync("git", ["diff", "--name-only", "--diff-filter=A", base + "...HEAD", "--"], {encoding:"utf8"}).trim().split("\n").filter(Boolean);
  for (const path of names) {
    if (!/\.(html|jsx|tsx|vue|svelte)$/.test(path) || /^(tests|docs|vendor|node_modules)\//.test(path)) continue;
    if (!existsSync(path)) continue;
    const source = readFileSync(path, "utf8");
    const marked = /(data-i18n|C10I18N|\buseTranslation\b|\bi18n\b|\btranslate\s*\()/i.test(source);
    assert.ok(marked, "NEW UI " + path + " needs shared i18n support. Register 3 reviewed language modes and update PR checklist.");
  }
  console.log("Checked newly added frontend screens against PR base: " + base.slice(0,12));
} else {
  console.log("BASE_SHA not provided; new-screen PR diff check deferred. Static contract verified.");
}
console.log("PASS: CORE 10 CENTRAL Bengali / Eng-Bng / English governance contract");
