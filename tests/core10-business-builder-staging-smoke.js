"use strict";
const assert=require("node:assert/strict");
const fs=require("node:fs");
const vm=require("node:vm");
const page=fs.readFileSync("core10-business-builder.html","utf8");
const stage=fs.readFileSync("core10-business-builder-staging.js","utf8");
const entry=fs.readFileSync("core10-owner-business-entry.js","utf8");
const owner=fs.readFileSync("owner.html","utf8");
for(const [name,script] of [["staging",stage],["owner-entry",entry]])new vm.Script(script,{filename:name+".js"});
for(const id of ["stagingBox","stagingStatus","legalEntity","createStagingDraft"]){
 assert.ok(page.includes('id="'+id+'"'),"Missing staging control "+id);
}
assert.match(page,/src="\.\/core10-business-builder-staging\.js"/);
assert.match(page,/src="\.\/core10-industry-client\.js"/);
assert.match(owner,/core10-owner-business-entry\.js/);
assert.match(stage,/getUser\(\)/);
assert.match(stage,/listLegalEntities\(\)/);
assert.match(stage,/setupDraft\(/);
assert.match(stage,/env\.stagingEnabled!==true\|\|env\.draftWritesEnabled!==true/);
assert.doesNotMatch(stage,/service_role|supabaseAdmin|\.rpc\s*\(/);
assert.match(entry,/state\.is_owner===true/);
assert.ok(!owner.includes("service_role"));
console.log("PASS: Owner entry, signed staging form, fail-closed gate and browser JS syntax");
