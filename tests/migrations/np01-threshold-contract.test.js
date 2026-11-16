"use strict";
const test=require("node:test"),assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path");
const dir=path.join(__dirname,"..","..","internal","migrations");
const up=fs.readFileSync(path.join(dir,"0014_np01_gov002_threshold_units.up.sql"),"utf8");
const down=fs.readFileSync(path.join(dir,"0014_np01_gov002_threshold_units.down.sql"),"utf8");
test("B-006 typed Owner threshold port persists immutable policy and no hardcoded units",()=>{
 assert.match(up,/CREATE TABLE core10\.approval_thresholds_v1/);
 assert.match(up,/precision_scale smallint NOT NULL CHECK/);
 assert.match(up,/unit_code ~ '\^\[A-Z\]/);
 assert.doesNotMatch(up,/unit_code IN \('KG','PCS','LB'\)/);
 assert.match(up,/BEFORE TRUNCATE ON core10\.approval_thresholds_v1/);
 assert.match(up,/FOR UPDATE/);
 assert.match(up,/FOR SHARE/);
 assert.match(up,/PERFORM core10\._append_canonical_audit_v1/);
 assert.match(up,/PERFORM core10\.assert_approval_threshold_v1\(v_policy\.id,p_payload\)/);
 assert.match(down,/CREATE OR REPLACE FUNCTION core10\.submit_typed_approval_v1/);
 assert.match(down,/DROP TABLE IF EXISTS core10\.approval_thresholds_v1/);
});
