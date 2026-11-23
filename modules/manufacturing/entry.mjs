import {mountManufacturing} from './workbench.mjs';
// Additive route contract: shell injects a verified context and its signed rpc function.
// This standalone development page is independent of retired app configuration and any hosted database.
if (window.CORE10ManufacturingContext && window.CORE10ManufacturingRPC) {
  window.CORE10ManufacturingDispose = mountManufacturing(document.querySelector('#manufacturing'), {
    context: window.CORE10ManufacturingContext, rpc: window.CORE10ManufacturingRPC
  });
}
