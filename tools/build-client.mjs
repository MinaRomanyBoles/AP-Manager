import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { execFileSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";
import { build } from "esbuild";
import { inject } from "postject";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const argv = process.argv.slice(2);
const flags = new Map();
for (let i = 0; i < argv.length; i += 2) flags.set(argv[i], argv[i + 1]);
const target = flags.get("--target") ?? "win-x64";
if (!["win-x64", "linux-x64"].includes(target)) throw new Error("Supported targets: win-x64, linux-x64");
const nodeVersion = "24.19.0";
if (process.versions.node !== nodeVersion) throw new Error(`Build with Node.js ${nodeVersion}; SEA generation and runtime versions must match.`);
const out = path.resolve(flags.get("--out") ?? path.join(root, "build-output", target));
const keyDir = path.resolve(flags.get("--keys-dir") ?? path.join(root, "owner-private"));
const work = path.join(out, ".build");
const client = path.join(out, "AP-Manager-Client-20261025");
const owner = path.join(out, "AP-Manager-Owner-Only");
for (const dir of [out, keyDir, work, client, owner]) fs.mkdirSync(dir, { recursive: true });

const privateKeyPath = path.join(keyDir, "activation-private-key.pem");
if (!fs.existsSync(privateKeyPath)) {
  const keys = crypto.generateKeyPairSync("ed25519");
  fs.writeFileSync(privateKeyPath, keys.privateKey.export({ type: "pkcs8", format: "pem" }), { mode: 0o600, flag: "wx" });
}
const privateKey = crypto.createPrivateKey(fs.readFileSync(privateKeyPath));
const publicKeyPath = path.join(keyDir, "activation-public-key.pem");
fs.writeFileSync(publicKeyPath, crypto.createPublicKey(privateKey).export({ type: "spki", format: "pem" }));
const stateSecretPath = path.join(keyDir, "state-secret");
if (!fs.existsSync(stateSecretPath)) fs.writeFileSync(stateSecretPath, crypto.randomBytes(32).toString("hex"), { mode: 0o600, flag: "wx" });

const ext = target.startsWith("win") ? ".exe" : "";
let nodeBinary = flags.get("--node-binary");
if (!nodeBinary) {
  if ((target === "win-x64" && process.platform === "win32") || (target === "linux-x64" && process.platform === "linux")) nodeBinary = process.execPath;
  else {
    nodeBinary = path.join(work, `node-${nodeVersion}${ext}`);
    execFileSync("curl", ["--fail", "--location", "--silent", "--show-error", `https://nodejs.org/dist/v${nodeVersion}/win-x64/node.exe`, "-o", nodeBinary], { stdio: "inherit" });
  }
}
nodeBinary = path.resolve(nodeBinary);
if (!fs.existsSync(nodeBinary)) throw new Error("Node target binary not found.");

function walk(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => entry.isDirectory() ? walk(path.join(dir, entry.name)) : [path.join(dir, entry.name)]);
}
const assetMap = {};
for (const filename of walk(path.join(root, "frontend", "dist"))) {
  if (filename.endsWith(".map")) throw new Error("Do not ship source maps.");
  assetMap[`frontend/${path.relative(path.join(root, "frontend", "dist"), filename).split(path.sep).join("/")}`] = filename;
}
assetMap["frontend/logo.png"] = path.join(root, "logo.png");
for (const script of ["Read-AccessPoints.ps1", "Get-Clients.ps1", "Update-AccessPoint.ps1", "Json-Helper.ps1", "Excel-Helper.ps1", "Cisco-Common.ps1", "AP-Manager-Core.ps1"]) {
  assetMap[`powershell/${script}`] = path.join(root, "Scripts", script);
}
assetMap["licensing/public-key.pem"] = publicKeyPath;
assetMap["licensing/state-secret"] = stateSecretPath;
const moduleDir = flags.get("--ssh-module");
if (!moduleDir || !fs.existsSync(path.join(moduleDir, "Posh-SSH.psd1"))) {
  throw new Error("Supply --ssh-module with the extracted, reviewed Posh-SSH 3.2.7 module directory.");
}
for (const filename of walk(moduleDir)) {
  const rel = path.relative(moduleDir, filename).split(path.sep).join("/");
  if (!rel.startsWith(".") && !rel.endsWith(".pdb")) assetMap[`dependency/Posh-SSH/${rel}`] = filename;
}

async function executable(entry, destination, assets = {}) {
  const bundle = path.join(work, `${path.basename(destination)}.cjs`);
  await build({ entryPoints: [entry], outfile: bundle, platform: "node", target: "node24", format: "cjs", bundle: true,
    minify: true, sourcemap: false, legalComments: "none", define: { "import.meta.url": JSON.stringify(pathToFileURL(path.join(root, "backend", "dist", "index.js")).href) } });
  const blob = path.join(work, `${path.basename(destination)}.blob`);
  const config = path.join(work, `${path.basename(destination)}.sea.json`);
  fs.writeFileSync(config, JSON.stringify({ main: bundle, output: blob, disableExperimentalSEAWarning: true, useSnapshot: false, useCodeCache: false, execArgv: [], execArgvExtension: "none", assets }));
  execFileSync(process.execPath, ["--experimental-sea-config", config], { stdio: "inherit" });
  fs.copyFileSync(nodeBinary, destination);
  fs.chmodSync(destination, 0o755);
  // Remove the original Node Authenticode certificate table before injection.
  // The finished client is unsigned and must be signed with the owner's certificate for a signed release.
  if (target.startsWith("win")) {
    const data = fs.readFileSync(destination);
    const pe = data.readUInt32LE(0x3c);
    if (data.toString("ascii", pe, pe + 4) !== "PE\0\0" || data.readUInt16LE(pe + 24) !== 0x20b) throw new Error("Expected a 64-bit PE file.");
    const certificateDirectory = pe + 24 + 112 + 4 * 8;
    data.writeUInt32LE(0, certificateDirectory); data.writeUInt32LE(0, certificateDirectory + 4);
    fs.writeFileSync(destination, data);
  }
  await inject(destination, "NODE_SEA_BLOB", fs.readFileSync(blob), { sentinelFuse: "NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2", overwrite: true });
}

await executable(path.join(root, "backend", "src", "client.ts"), path.join(client, `AP-Manager${ext}`), assetMap);
await executable(path.join(root, "tools", "activation-tool.ts"), path.join(owner, `AP-Manager-Activation${ext}`));

const workbook = flags.get("--workbook");
if (!workbook || !fs.existsSync(workbook)) throw new Error("Supply --workbook with a validated AP-Info-Manager.xlsx workbook/template.");
fs.copyFileSync(workbook, path.join(client, "AP-Info-Manager.xlsx"));
for (const name of ["activation-private-key.pem", "activation-public-key.pem", "state-secret"]) fs.copyFileSync(path.join(keyDir, name), path.join(owner, name));
fs.copyFileSync(path.join(root, "Docs", "CLIENT-README-AR-EN.txt"), path.join(client, "READ-ME-AR-EN.txt"));
fs.copyFileSync(path.join(root, "Docs", "OWNER-README-AR-EN.txt"), path.join(owner, "READ-ME-OWNER-AR-EN.txt"));

// Include dependency license notices alongside the executable.
let notices = "AP Manager third-party software notices\n\n";
const nodeLicensePath = flags.get("--node-license");
if (!nodeLicensePath || !fs.existsSync(nodeLicensePath)) throw new Error("Supply --node-license with the Node.js LICENSE file for this runtime version.");
notices += "Node.js " + nodeVersion + "\n" + fs.readFileSync(nodeLicensePath, "utf8") + "\n\n";
for (const modules of ["backend", "frontend"]) {
  const modulesRoot = path.join(root, modules, "node_modules");
  for (const filename of walk(modulesRoot).filter(f => /[\\/]licen[sc]e(?:\.[^.\\/]+)?$/i.test(f))) {
    notices += path.relative(root, filename) + "\n" + fs.readFileSync(filename, "utf8") + "\n\n";
  }
}
const sshLicense = flags.get("--ssh-license");
if (!sshLicense || !fs.existsSync(sshLicense)) throw new Error("Supply --ssh-license with the Posh-SSH license.");
notices += "Posh-SSH 3.2.7\n" + fs.readFileSync(sshLicense, "utf8") + "\n";
for (const dir of [client, owner]) fs.writeFileSync(path.join(dir, "THIRD-PARTY-NOTICES.txt"), notices);
const files = walk(client).map(filename => ({ path: path.relative(client, filename), sha256: crypto.createHash("sha256").update(fs.readFileSync(filename)).digest("hex"), bytes: fs.statSync(filename).size }));
if (walk(client).some(f => /(?:private-key|\.(?:ps1|ts|tsx|cjs|map)$)/i.test(f))) throw new Error("Application source or a signing key leaked into the client package.");
fs.writeFileSync(path.join(out, "build-manifest.json"), JSON.stringify({ target, nodeVersion, trialExpiresAt: "2026-10-25T21:00:00.000Z", clientFiles: files }, null, 2));
console.log(`Client: ${client}\nOwner only: ${owner}`);
