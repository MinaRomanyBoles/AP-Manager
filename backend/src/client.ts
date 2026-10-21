import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync, spawn } from "node:child_process";
import { getAsset, getAssetKeys } from "node:sea";
import { configureClientLicense, LicenseManager } from "./licensing/manager.js";
import { HOST, PORT, PROJECT_ROOT } from "./config.js";
import { startServer } from "./index.js";

function openBrowser() {
  const command = process.platform === "win32"
    ? path.join(process.env.SystemRoot ?? "C:\\Windows", "System32", "rundll32.exe") : "xdg-open";
  const args = process.platform === "win32" ? ["url.dll,FileProtocolHandler", `http://${HOST}:${PORT}`] : [`http://${HOST}:${PORT}`];
  const child = spawn(command, args, { detached: true, windowsHide: true, stdio: "ignore" });
  child.on("error", () => { console.log(`Open http://${HOST}:${PORT} in your browser.`); });
  child.unref();
}

async function main() {
  if (process.argv.includes("--self-test")) {
    // A read-only packaging check, never a test clock or a licensing bypass.
    for (const name of ["frontend/index.html", "powershell/Read-AccessPoints.ps1", "licensing/public-key.pem", "licensing/state-secret"]) {
      if (getAsset(name).byteLength === 0) throw new Error(`Missing embedded asset: ${name}`);
    }
    console.log("AP Manager client assets OK. Trial ends 2026-10-26 00:00 Africa/Cairo.");
    return;
  }
  if (process.platform !== "win32") throw new Error("This client edition requires Windows 10/11 (64-bit).");
  const systemRoot = process.env.SystemRoot ?? "C:\\Windows";
  const registry = execFileSync(path.join(systemRoot, "System32", "reg.exe"),
    ["query", "HKLM\\SOFTWARE\\Microsoft\\Cryptography", "/v", "MachineGuid", "/reg:64"],
    { encoding: "utf8", windowsHide: true });
  const machineGuid = registry.match(/MachineGuid\s+REG_SZ\s+([^\r\n]+)/i)?.[1]?.trim();
  if (!machineGuid) throw new Error("Could not read this computer's machine ID.");
  const machineId = "APM-" + crypto.createHash("sha256").update(`AP-Manager\n${machineGuid.toLowerCase()}`).digest("hex").slice(0, 32).toUpperCase();
  const localData = process.env.LOCALAPPDATA ?? path.join(os.homedir(), "AppData", "Local");
  const dependencies = path.join(localData, "AP-Manager", "Dependencies");
  for (const asset of getAssetKeys().filter(key => key.startsWith("dependency/"))) {
    const relative = asset.slice("dependency/".length);
    const destination = path.join(dependencies, relative);
    const content = Buffer.from(getAsset(asset));
    fs.mkdirSync(path.dirname(destination), { recursive: true });
    if (!fs.existsSync(destination) || !fs.readFileSync(destination).equals(content)) fs.writeFileSync(destination, content);
  }
  process.env.PSModulePath = `${dependencies};${process.env.PSModulePath ?? ""}`;
  const manager = new LicenseManager({
    machineId,
    publicKey: getAsset("licensing/public-key.pem", "utf8"),
    stateSecret: getAsset("licensing/state-secret", "utf8"),
    stateDirectory: path.join(localData, "AP-Manager", "Licensing"),
  });
  configureClientLicense(manager);
  for (const directory of ["Logs", "Backups", "Runtime"]) fs.mkdirSync(path.join(PROJECT_ROOT, directory), { recursive: true });
  const server = startServer();
  server.on("listening", () => {
    console.log("AP Manager is running. Keep this window open. Press Ctrl+C to stop.");
    console.log("Trial: valid through 25 October 2026, Cairo time. Activation is available in the dashboard.");
    manager.status();
    openBrowser();
  });
  server.on("error", async (error: NodeJS.ErrnoException) => {
    if (error.code === "EADDRINUSE") {
      try {
        const response = await fetch(`http://${HOST}:${PORT}/api/license/status`);
        const body = await response.json() as { machineId?: string };
        if (body.machineId === machineId) { openBrowser(); return; }
      } catch { /* Explain the port conflict below. */ }
      throw new Error("Port 8787 is already in use. Close the other AP Manager instance and try again.");
    }
    throw error;
  });
  const stop = () => { server.close(); server.closeIdleConnections(); process.exit(0); };
  process.once("SIGINT", stop);
  process.once("SIGTERM", stop);
}

main().catch((error) => { console.error(`AP Manager: ${(error as Error).message}`); process.exitCode = 1; });
