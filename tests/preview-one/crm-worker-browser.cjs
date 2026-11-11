"use strict";
// Run the unchanged, comprehensive original CRM browser journey through the actual
// Worker route/headers/allowlist, instead of the original test's static filesystem server.
const http = require("node:http");
const fs = require("node:fs/promises");
const path = require("node:path");
const assert = require("node:assert/strict");

(async () => {
  const { default: worker } = await import("../../preview/worker.mjs");
  const root = path.resolve(__dirname, "../..");
  const previousFetch = globalThis.fetch;
  globalThis.fetch = async url => {
    const parsed = new URL(String(url));
    assert.equal(parsed.hostname, "raw.githubusercontent.com");
    assert.match(parsed.pathname, /^\/mistybari99\/CORE-10-CENTRAL\/3936e1e7bf10320e1164252ec5fa73c0b6945759\/core10-crm-lifecycle(?:-[a-z]+)*\.(?:html|js|css)$/);
    return new Response(await fs.readFile(path.join(root, parsed.pathname.split("/").pop())), { status: 200 });
  };
  const staticServer = require("../e2e/static_server");
  staticServer.createServer = () => {
    const server = http.createServer(async (req, res) => {
      try {
        const response = await worker.fetch(new Request("http://127.0.0.1" + req.url, { method: req.method }));
        res.writeHead(response.status, Object.fromEntries(response.headers));
        res.end(Buffer.from(await response.arrayBuffer()));
      } catch (error) { res.writeHead(500); res.end(error.message); }
    });
    server.on("close", () => { globalThis.fetch = previousFetch; });
    return server;
  };
  if (process.env.CORE10_CHROMIUM_PATH) {
    const { chromium } = require("playwright");
    const launch = chromium.launch.bind(chromium);
    chromium.launch = options => launch({ ...options, executablePath: process.env.CORE10_CHROMIUM_PATH });
  }
  require("../e2e/core10-a056-crm-browser.js");
})().catch(error => { console.error(error); process.exitCode = 1; });
