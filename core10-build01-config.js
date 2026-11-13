/* Build 01: locked by default. The isolated loopback gateway supplies its own
 * explicit configuration. Never inherit the legacy/production BOS_CONFIG. */
window.CORE10_BUILD01_CONFIG = Object.freeze({
  enabled: false,
  mode: "isolated-development",
  url: "",
  publishableKey: ""
});
