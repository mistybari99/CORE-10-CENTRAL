"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const read = path => fs.readFileSync(path,"utf8");
const targets = {
  "CLAUDE.md": ["CORE-10-CENTRAL","CORE10_GITHUB_FIRST_AI_PROTOCOL.md","CURRENT_HANDOFF.md","C10-A004","Draft PR #8"],
  "AGENTS.md": ["CORE-10-CENTRAL","CORE10_GITHUB_FIRST_AI_PROTOCOL.md","CURRENT_HANDOFF.md","GitHub-first"],
  "docs/development/CORE10_GITHUB_FIRST_AI_PROTOCOL.md": ["GitHub-first","C10-A004","Decision Book","Islamia","read-only","GitHub","Supabase","CURRENT_HANDOFF.md","A024","A025"],
  "docs/development/GITHUB_SUPABASE_MIGRATION_RUNBOOK.md": ["GitHub","Supabase","schema-only","staging","migration","drift","approval","db reset --remote"],
  "docs/development/CURRENT_HANDOFF.md": ["C10-A004","pull/8","security/c10-a004-islamia-cost-rpc-hardening","08a6b1a5","42729359046","NEXT","Claude","ChatGPT"]
};
for(const [path,terms] of Object.entries(targets)){
  assert(fs.existsSync(path),`Missing instruction artifact: ${path}`);
  const source=read(path);
  assert(source.length>200,`Empty instruction file: ${path}`);
  for(const term of terms)assert(source.includes(term),`Missing canonical instruction "${term}" in ${path}`);
}
const claude=read("CLAUDE.md"),agent=read("AGENTS.md");
for(const s of ["docs/development/CORE10_GITHUB_FIRST_AI_PROTOCOL.md","docs/development/CURRENT_HANDOFF.md"]){
  assert(claude.includes(s)&&agent.includes(s),"agents must use the same canonical docs");
}
assert(read("docs/development/GITHUB_SUPABASE_MIGRATION_RUNBOOK.md").includes("no such"),"must not pretend deployment is configured");
process.stdout.write("PASS: Claude/ChatGPT common GitHub-first protocol, A004 resume checkpoint and DB release gates are versioned.\n");
