"use strict";
/* Honest placeholders: registered so coverage is visible, but they REFUSE to run. */
const { registerModel } = require("../lib/kernel");
registerModel({ id: "X01", version: "0.0.0", family: "calibrated_uncertainty", title: { en: "Calibrated probability / Monte Carlo", bn: "ক্যালিব্রেটেড সম্ভাব্যতা / মন্টে কার্লো" }, status: "research_only", reason: "Probabilities require validated distribution and correlation evidence from verified actuals (U14/R102). Scenario ranges (conservative/baseline/optimistic) are provided instead.", inputs: [], outputs: [], industries: [], explain: null });
