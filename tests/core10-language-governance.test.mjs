import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createI18n, SUPPORTED_LOCALES } from "../preview/i18n.mjs";

test("C10 language governance: new screens inherit three modes with natural familiar terms", () => {
  assert.deepEqual(SUPPORTED_LOCALES, ["bn-BD", "bn-BD-mixed", "en"]);
  const t = createI18n("bn-BD");
  assert.equal(t.t("nav.inventory"), "স্টক");
  assert.equal(t.t("common.approval"), "অ্যাপ্রুভাল (অনুমোদনের ধাপ)");
  t.setLocale("bn-BD-mixed");
  assert.equal(t.t("nav.inventory"), "Stock");
  assert.equal(t.t("common.approval"), "Approval (অনুমোদনের ধাপ)");
  t.setLocale("en");
  assert.equal(t.t("nav.inventory"), "Inventory");
  assert.equal(t.t("common.approval"), "Approval");
});

test("C10 language governance: agent entrypoint and policy require every UI module to follow it", () => {
  const agents = readFileSync(new URL("../AGENTS.md", import.meta.url), "utf8");
  const contract = readFileSync(new URL("../docs/ux/C10_LANGUAGE_CONTRACT.md", import.meta.url), "utf8");
  assert.match(agents, /all future ERP UI work/i);
  assert.match(agents, /C10_LANGUAGE_CONTRACT.md/);
  for(const name of ["Bengali","Eng/Bng","English"]) {
    assert.ok(agents.includes(name));
    assert.ok(contract.includes(name));
  }
  assert.match(contract, /স্টকের হিসাব মিলিয়ে নিন/);
  assert.match(contract, /Stock-এর হিসাব মিলিয়ে নিন/);
  assert.match(contract, /No server\/network\/AI translation at runtime/);
});
