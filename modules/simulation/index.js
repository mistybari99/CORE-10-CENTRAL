"use strict";
/* C10-A025 simulation engine entry. Load order matters: models register into the immutable registry. */
require("./models/core"); require("./models/finance"); require("./models/ops"); require("./models/not_built");
module.exports = Object.assign({}, require("./lib/decimal"), require("./lib/kernel"), { sha256: require("./lib/sha256"), units: require("./lib/units"),
  lib: { scenario: require("./lib/scenario"), quick: require("./lib/quick"), analysis: require("./lib/analysis"), decisions: require("./lib/decisions"), reports: require("./lib/reports"), context: require("./lib/context"), demo: require("./lib/demo-data"), coverage: require("./lib/coverage"), packs: require("./lib/packs"), uncertainty: require("./lib/uncertainty") } });
