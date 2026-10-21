import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { createInterface } from "node:readline/promises";
import { isSea } from "node:sea";

// Owner-only tool. The signing key is always a separate private file.
async function main() {
  const root = isSea() ? path.dirname(process.execPath) : process.cwd();
  const args = process.argv.slice(2);
  const flags = new Map<string, string>();
  for (let i = 0; i < args.length; i += 2) flags.set(args[i], args[i + 1]);
  const interactive = args.length === 0;
  const rl = interactive ? createInterface({ input: process.stdin, output: process.stdout }) : undefined;
  try {
    console.log("AP Manager — OWNER activation tool. Do not share this folder with clients.");
    const machineId = (flags.get("--machine") ?? await rl?.question("Client machine ID (APM-...): ") ?? "").trim().toUpperCase();
    const customer = (flags.get("--customer") ?? await rl?.question("Customer name: ") ?? "").trim();
    const date = (flags.get("--through") ?? await rl?.question("Valid THROUGH Cairo date (YYYY-MM-DD): ") ?? "").trim();
    if (!/^APM-[A-F0-9]{32}$/.test(machineId)) throw new Error("Invalid machine ID.");
    if (!customer || customer.length > 200) throw new Error("Enter a customer name (1–200 characters).");
    const expiresAt = endOfCairoDate(date);
    const issuedAt = new Date().toISOString();
    if (Date.parse(expiresAt) <= Date.parse(issuedAt)) throw new Error("The expiry date must be in the future.");
    const keyPath = flags.get("--key") ?? path.join(root, "activation-private-key.pem");
    const key = crypto.createPrivateKey(fs.readFileSync(keyPath));
    if (key.asymmetricKeyType !== "ed25519") throw new Error("An Ed25519 private key is required.");
    const bytes = Buffer.from(JSON.stringify({ version: 1, product: "AP-Manager", machineId, customer, issuedAt, expiresAt }));
    const token = `${bytes.toString("base64url")}.${crypto.sign(null, bytes, key).toString("base64url")}`;
    const destination = flags.get("--out") ?? path.join(root, `${machineId}-${date}.aplicense`);
    fs.writeFileSync(destination, token + "\n", { mode: 0o600, flag: "wx" });
    console.log(`\nActivation file: ${destination}\nValid through ${date}, Cairo time.\n\n${token}\n`);
    if (interactive) await rl!.question("Press Enter to close.");
  } finally { rl?.close(); }
}

export function endOfCairoDate(date: string): string {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new Error("Use YYYY-MM-DD for the date.");
  const day = Date.parse(`${date}T00:00:00Z`);
  if (!Number.isFinite(day) || new Date(day).toISOString().slice(0, 10) !== date) throw new Error("Invalid calendar date.");
  const nextMidnight = day + 86_400_000;
  const format = new Intl.DateTimeFormat("en-CA", { timeZone: "Africa/Cairo", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23" });
  let candidate = nextMidnight;
  for (let i = 0; i < 4; i++) {
    const parts = Object.fromEntries(format.formatToParts(new Date(candidate)).map(p => [p.type, p.value]));
    const shown = Date.UTC(+parts.year, +parts.month - 1, +parts.day, +parts.hour, +parts.minute, +parts.second);
    candidate += nextMidnight - shown;
  }
  return new Date(candidate).toISOString();
}

// Tests import the date conversion without starting the interactive CLI.
if (isSea() || process.argv[1]?.endsWith("activation-tool.ts")) {
  main().catch(async error => {
    console.error((error as Error).message);
    process.exitCode = 1;
    if (process.argv.length <= 2) {
      const rl = createInterface({ input: process.stdin, output: process.stdout });
      await rl.question("Press Enter to close."); rl.close();
    }
  });
}
