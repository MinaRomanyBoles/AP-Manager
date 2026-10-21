import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { performance } from "node:perf_hooks";
import { CLOCK_TOLERANCE_MS, PRODUCT, TRIAL_EXPIRES_AT, TRIAL_START, type LicensePayload, type LicenseStatus } from "./policy.js";

interface State { version: 1; lastSeen: number; trialExpired: boolean; mac: string }
interface Options {
  machineId: string;
  publicKey: string;
  stateDirectory: string;
  stateSecret: string;
  now?: () => number;
}

export class LicenseManager {
  private state?: State;
  private lastWrite = 0;
  private token = "";
  private payload?: LicensePayload;
  private readonly now: () => number;
  private readonly stateFile: string;
  private readonly licenseFile: string;

  constructor(private readonly options: Options) {
    const startedAt = Date.now();
    const monotonicStart = performance.now();
    this.now = options.now ?? (() => Math.max(Date.now(), startedAt + performance.now() - monotonicStart));
    this.stateFile = path.join(options.stateDirectory, "usage.json");
    this.licenseFile = path.join(options.stateDirectory, "license.aplicense");
  }

  private mac(lastSeen: number, trialExpired: boolean): string {
    return crypto.createHmac("sha256", this.options.stateSecret)
      .update(JSON.stringify([PRODUCT, this.options.machineId, lastSeen, trialExpired])).digest("hex");
  }

  private load() {
    if (this.state) return;
    fs.mkdirSync(this.options.stateDirectory, { recursive: true });
    let state: State;
    if (fs.existsSync(this.stateFile)) {
      state = JSON.parse(fs.readFileSync(this.stateFile, "utf8"));
      if (state.version !== 1 || !Number.isFinite(state.lastSeen) || typeof state.trialExpired !== "boolean" ||
        typeof state.mac !== "string" || state.mac !== this.mac(state.lastSeen, state.trialExpired)) {
        throw new Error("License history could not be verified. Contact the software provider.");
      }
    } else {
      const now = this.now();
      state = { version: 1, lastSeen: now, trialExpired: now >= Date.parse(TRIAL_EXPIRES_AT), mac: "" };
    }
    // Write before accepting operations, including on the first launch.
    this.writeState(state);
    this.state = state;
    if (fs.existsSync(this.licenseFile)) {
      this.token = fs.readFileSync(this.licenseFile, "utf8").trim();
      try { this.payload = this.verifyToken(this.token); } catch { this.payload = undefined; }
    }
  }

  private writeState(state: State) {
    state.mac = this.mac(state.lastSeen, state.trialExpired);
    const temp = `${this.stateFile}.${process.pid}.tmp`;
    fs.writeFileSync(temp, JSON.stringify(state), { mode: 0o600 });
    fs.renameSync(temp, this.stateFile);
    this.lastWrite = state.lastSeen;
  }

  private verifyToken(token: string): LicensePayload {
    if (token.length > 8192 || !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(token)) throw new Error("Invalid activation key.");
    const [encoded, signature] = token.split(".");
    const bytes = Buffer.from(encoded, "base64url");
    if (!crypto.verify(null, bytes, this.options.publicKey, Buffer.from(signature, "base64url"))) {
      throw new Error("Invalid activation signature.");
    }
    const payload = JSON.parse(bytes.toString("utf8")) as LicensePayload;
    if (payload.version !== 1 || payload.product !== PRODUCT || payload.machineId !== this.options.machineId ||
      typeof payload.customer !== "string" || payload.customer.length > 200 ||
      typeof payload.issuedAt !== "string" || typeof payload.expiresAt !== "string" ||
      !Number.isFinite(Date.parse(payload.issuedAt)) || !Number.isFinite(Date.parse(payload.expiresAt)) ||
      Date.parse(payload.expiresAt) <= Date.parse(payload.issuedAt)) {
      throw new Error("This activation key is invalid or belongs to another computer.");
    }
    return payload;
  }

  status(): LicenseStatus {
    const base = { machineId: this.options.machineId, expiresAt: TRIAL_EXPIRES_AT, timeZone: "Africa/Cairo" as const };
    try {
      this.load();
      const state = this.state!;
      const wallNow = this.now();
      if (wallNow < Date.parse(TRIAL_START) - CLOCK_TOLERANCE_MS || wallNow < state.lastSeen - CLOCK_TOLERANCE_MS) {
        return { ...base, allowed: false, reason: "clock_rollback", error: "Correct the computer date and time, then restart AP Manager." };
      }
      const now = Math.max(wallNow, state.lastSeen);
      const expiredBefore = state.trialExpired;
      state.lastSeen = now;
      state.trialExpired ||= now >= Date.parse(TRIAL_EXPIRES_AT);
      if (now - this.lastWrite >= 30_000 || expiredBefore !== state.trialExpired) this.writeState(state);
      const validLicense = this.payload && Date.parse(this.payload.issuedAt) <= now + CLOCK_TOLERANCE_MS &&
        Date.parse(this.payload.expiresAt) > now;
      if (validLicense) return { ...base, allowed: true, reason: "activated", expiresAt: this.payload!.expiresAt, customer: this.payload!.customer };
      if (!state.trialExpired && now < Date.parse(TRIAL_EXPIRES_AT)) return { ...base, allowed: true, reason: "trial" };
      return { ...base, allowed: false, reason: "expired" };
    } catch {
      return { ...base, allowed: false, reason: "state_error", error: "License storage is unavailable or damaged. Check folder permissions or contact the software provider." };
    }
  }

  activate(token: string): LicenseStatus {
    const status = this.status();
    if (["clock_rollback", "state_error"].includes(status.reason)) throw new Error(status.error);
    const payload = this.verifyToken(token.trim());
    const now = Math.max(this.now(), this.state!.lastSeen);
    if (Date.parse(payload.issuedAt) > now + CLOCK_TOLERANCE_MS) throw new Error("Activation key is not yet valid. Check the computer clock.");
    if (Date.parse(payload.expiresAt) <= now) throw new Error("This activation key has expired.");
    const temp = `${this.licenseFile}.${process.pid}.tmp`;
    fs.writeFileSync(temp, token.trim(), { mode: 0o600 });
    fs.renameSync(temp, this.licenseFile);
    this.token = token.trim();
    this.payload = payload;
    return this.status();
  }

  assertAllowed(): void {
    const status = this.status();
    if (!status.allowed) throw new Error(status.error ?? "AP Manager has expired. Activation is required.");
  }
}

let clientLicense: LicenseManager | undefined;
export function configureClientLicense(manager: LicenseManager) { clientLicense = manager; }
export function getClientLicense() { return clientLicense; }
export function assertClientLicense() { clientLicense?.assertAllowed(); }
