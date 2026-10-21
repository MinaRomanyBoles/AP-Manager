import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import http from "node:http";
import { after, test } from "node:test";
import { LicenseManager, configureClientLicense } from "../backend/src/licensing/manager.js";
import { TRIAL_EXPIRES_AT } from "../backend/src/licensing/policy.js";
import { endOfCairoDate } from "../tools/activation-tool.js";

const keys = crypto.generateKeyPairSync("ed25519");
const publicKey = keys.publicKey.export({ type: "spki", format: "pem" }).toString();
const machineId = "APM-0123456789ABCDEF0123456789ABCDEF";
const directories: string[] = [];
const cutoff = Date.parse(TRIAL_EXPIRES_AT);

function fixture(start = cutoff - 60_000) {
  let now = start;
  const stateDirectory = fs.mkdtempSync(path.join(os.tmpdir(), "ap-license-test-"));
  directories.push(stateDirectory);
  const options = { machineId, publicKey, stateDirectory, stateSecret: "test-secret", now: () => now };
  return { manager: new LicenseManager(options), options, setNow: (value: number) => { now = value; } };
}
function token(overrides: Record<string, unknown> = {}, privateKey = keys.privateKey): string {
  const bytes = Buffer.from(JSON.stringify({ version: 1, product: "AP-Manager", machineId, customer: "Test Customer",
    issuedAt: "2026-10-21T00:00:00.000Z", expiresAt: "2026-11-25T22:00:00.000Z", ...overrides }));
  return `${bytes.toString("base64url")}.${crypto.sign(null, bytes, privateKey).toString("base64url")}`;
}
after(() => { for (const dir of directories) fs.rmSync(dir, { recursive: true, force: true }); });

test("inclusive Cairo deadline and exact exclusive UTC boundary", () => {
  assert.equal(endOfCairoDate("2026-10-25"), TRIAL_EXPIRES_AT);
  assert.equal(endOfCairoDate("2026-11-25"), "2026-11-25T22:00:00.000Z");
  assert.throws(() => endOfCairoDate("2026-02-30"));
  const f = fixture(cutoff - 1);
  assert.equal(f.manager.status().allowed, true);
  f.setNow(cutoff);
  assert.equal(f.manager.status().reason, "expired");
  assert.equal(f.manager.status().allowed, false);
});

test("first launch after expiry is blocked without deleting user data", () => {
  const f = fixture(cutoff + 1);
  const data = path.join(f.options.stateDirectory, "customer-workbook.xlsx");
  fs.writeFileSync(data, "untouched");
  assert.equal(f.manager.status().reason, "expired");
  assert.equal(fs.readFileSync(data, "utf8"), "untouched");
});

test("renewal unlocks after expiry and survives restarting", () => {
  const f = fixture(cutoff + 1000);
  assert.equal(f.manager.status().allowed, false);
  assert.equal(f.manager.activate(token()).reason, "activated");
  assert.equal(new LicenseManager(f.options).status().allowed, true);
  f.setNow(Date.parse("2026-11-25T22:00:00Z"));
  assert.equal(f.manager.status().allowed, false);
});

test("tampering, wrong signing keys and a different machine are rejected", () => {
  const f = fixture(cutoff + 1000);
  assert.throws(() => f.manager.activate("fake.key"));
  assert.throws(() => f.manager.activate(token({ customer: "Other" }, crypto.generateKeyPairSync("ed25519").privateKey)));
  assert.throws(() => f.manager.activate(token({ machineId: "APM-FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF" })));
  assert.throws(() => f.manager.activate(token({ product: "Other" })));
  assert.equal(f.manager.status().allowed, false);
});

test("expired and future-issued activation keys are rejected", () => {
  const f = fixture(cutoff + 1000);
  assert.throws(() => f.manager.activate(token({ expiresAt: "2026-10-22T00:00:00Z" })));
  assert.throws(() => f.manager.activate(token({ issuedAt: "2026-10-27T00:00:00Z" })));
  assert.equal(f.manager.status().allowed, false);
});

test("rolling the clock back after expiry does not restore trial access", () => {
  const f = fixture();
  assert.equal(f.manager.status().allowed, true);
  f.setNow(cutoff);
  assert.equal(f.manager.status().allowed, false);
  f.setNow(cutoff - 120_000);
  assert.equal(f.manager.status().allowed, false);
  f.setNow(cutoff - 3_600_000);
  assert.equal(new LicenseManager(f.options).status().reason, "clock_rollback");
  f.setNow(cutoff + 5000);
  assert.equal(f.manager.status().reason, "expired");
});

test("tampered history and unwritable state fail closed", () => {
  const f = fixture(); f.manager.status();
  fs.writeFileSync(path.join(f.options.stateDirectory, "usage.json"), JSON.stringify({ version: 1, lastSeen: cutoff - 1, trialExpired: false, mac: "fake" }));
  assert.equal(new LicenseManager(f.options).status().reason, "state_error");
  const bad = new LicenseManager({ ...f.options, stateDirectory: path.join(f.options.stateDirectory, "usage.json", "child") });
  assert.equal(bad.status().allowed, false);
});

test("backdating a new install to before this build is blocked", () => {
  const f = fixture(Date.parse("2026-10-01T00:00:00Z"));
  assert.equal(f.manager.status().reason, "clock_rollback");
});

test("API routes and queued PowerShell work are guarded; activation remains reachable", async () => {
  const f = fixture(cutoff - 1000);
  configureClientLicense(f.manager);
  const { default: app } = await import("../backend/src/index.js");
  const { runPowerShellScript } = await import("../backend/src/services/powershell.js");
  const server = app.listen(0, "127.0.0.1");
  await new Promise<void>(resolve => server.once("listening", resolve));
  const address = server.address() as { port: number };
  const url = `http://127.0.0.1:${address.port}`;
  const headers = { Host: "127.0.0.1:8787" };
  // Node fetch deliberately normalizes Host; use raw HTTP to test rebinding.
  const fetch = (target: string, options: { method?: string; headers?: Record<string, string>; body?: string } = {}) =>
    new Promise<{ status: number; json: () => Promise<any> }>((resolve, reject) => {
      const req = http.request(target, options, res => {
        let body = ""; res.setEncoding("utf8");
        res.on("data", chunk => { body += chunk; });
        res.on("end", () => resolve({ status: res.statusCode!, json: async () => JSON.parse(body) }));
      });
      req.on("error", reject); req.end(options.body);
    });
  try {
    assert.equal((await fetch(`${url}/api/health`, { headers })).status, 200);
    f.setNow(cutoff);
    for (const [route, method] of [["/api/health", "GET"], ["/api/logs", "GET"], ["/api/access-points/2/apply", "POST"], ["/api/access-points/get-clients-all", "POST"]]) {
      assert.equal((await fetch(url + route, { method, headers })).status, 402, route);
    }
    assert.throws(() => runPowerShellScript({ scriptName: "Get-Clients.ps1", args: ["-RowNumber", "2"] }), /expired/);
    assert.equal((await fetch(`${url}/api/license/status`, { headers })).status, 200);
    assert.equal((await fetch(`${url}/api/license/activate`, { method: "POST", headers: { ...headers, "Content-Type": "application/json" }, body: JSON.stringify({ token: token() }) })).status, 403);
    const csrf = await (await fetch(`${url}/api/csrf-token`, { headers })).json() as { csrfToken: string };
    const response = await fetch(`${url}/api/license/activate`, { method: "POST", headers: { ...headers, "Content-Type": "application/json", "X-CSRF-Token": csrf.csrfToken }, body: JSON.stringify({ token: token() }) });
    assert.equal(response.status, 200);
    assert.equal((await fetch(`${url}/api/health`, { headers })).status, 200);
    assert.equal((await fetch(`${url}/api/license/status`, { headers: { Host: "attacker.example" } })).status, 403);
  } finally { server.closeAllConnections(); await new Promise<void>(resolve => server.close(() => resolve())); }
});
