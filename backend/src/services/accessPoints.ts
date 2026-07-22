import fs from "node:fs";
import path from "node:path";
import { BACKUPS_DIR, EXCEL_PATH, LOGS_DIR, RUNTIME_DIR } from "../config.js";
import { runPowerShellScript, type PowerShellResult } from "./powershell.js";

export interface AccessPointPublic {
  rowNumber: number;
  accessPointName: string;
  accessPointIP: string;
  macAddress: string;
  accessUser: string;
  hasAccessPassword: boolean;
  currentSSID: string;
  newWiFiSSID: string;
  hasNewWiFiPassword: boolean;
  clients: string | number;
  connectionStatus: string;
  lastUpdated: string;
}

export interface AccessPointsResponse {
  success: boolean;
  source?: string;
  lastSync?: string;
  accessPoints?: AccessPointPublic[];
  error?: string;
}

export interface OperationResult {
  success: boolean;
  rowNumber?: number;
  accessPointName?: string;
  accessPointIP?: string;
  clients?: number | string;
  connectionType?: string;
  logPath?: string;
  durationSeconds?: number;
  lastUpdated?: string;
  stage?: string;
  error?: string;
  oldSSID?: string;
  newSSID?: string;
  passwordUpdated?: boolean;
  sshV2?: string;
  configurationSaved?: boolean;
  backupPath?: string;
}

const IP_REGEX =
  /^(?:(?:25[0-5]|2[0-4]\d|[01]?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d?\d)$/;

export function isValidIp(ip: string): boolean {
  return IP_REGEX.test(ip);
}

export function isValidRowNumber(row: number): boolean {
  return Number.isInteger(row) && row >= 2 && row <= 10_000;
}

function runtimeJsonPath(prefix: string): string {
  fs.mkdirSync(RUNTIME_DIR, { recursive: true });
  return path.join(RUNTIME_DIR, `${prefix}-${Date.now()}.json`);
}

function readScriptPayload<T>(result: PowerShellResult, outputJsonPath: string): T {
  if (result.json && typeof result.json === "object") {
    return result.json as T;
  }

  if (fs.existsSync(outputJsonPath)) {
    const raw = fs.readFileSync(outputJsonPath, "utf8").replace(/^\uFEFF/, "");
    return JSON.parse(raw) as T;
  }

  const trimmed = result.stdout.trim().replace(/^\uFEFF/, "");
  const jsonStart = trimmed.indexOf("{");
  if (jsonStart >= 0) {
    try {
      return JSON.parse(trimmed.slice(jsonStart)) as T;
    } catch {
      // fall through
    }
  }

  const details = result.stderr.trim() || trimmed;
  throw new Error(
    details || `PowerShell script failed (exit ${result.exitCode}) without returning JSON.`,
  );
}

function cleanupJsonFile(outputJsonPath: string) {
  try {
    if (fs.existsSync(outputJsonPath)) {
      fs.unlinkSync(outputJsonPath);
    }
  } catch {
    // ignore
  }
}

export async function loadAccessPoints(): Promise<AccessPointsResponse> {
  if (!fs.existsSync(EXCEL_PATH)) {
    return { success: false, error: "Excel file not found: AP-Info-Manager.xlsx" };
  }

  const outputJsonPath = runtimeJsonPath("ap-read");

  const result = await runPowerShellScript({
    scriptName: "Read-AccessPoints.ps1",
    args: [],
    outputJsonPath,
    timeoutMs: 60_000,
  });

  try {
    return readScriptPayload<AccessPointsResponse>(result, outputJsonPath);
  } finally {
    cleanupJsonFile(outputJsonPath);
  }
}

export async function getClientsForRow(rowNumber: number, showWindow = false): Promise<OperationResult> {
  if (!isValidRowNumber(rowNumber)) {
    throw new Error("Invalid row number.");
  }

  const outputJsonPath = runtimeJsonPath(`clients-row-${rowNumber}`);

  const result = await runPowerShellScript({
    scriptName: "Get-Clients.ps1",
    args: ["-RowNumber", String(rowNumber)],
    outputJsonPath,
    showWindow,
    timeoutMs: 120_000,
  });

  try {
    const payload = readScriptPayload<OperationResult>(result, outputJsonPath);
    if (!payload.success) {
      throw new Error(payload.error ?? "Get Clients failed.");
    }
    return payload;
  } finally {
    cleanupJsonFile(outputJsonPath);
  }
}

export async function applyChangesForRow(
  rowNumber: number,
  applyMode: "all" | "ssid" | "password" = "all",
  showWindow = false,
): Promise<OperationResult> {
  if (!isValidRowNumber(rowNumber)) {
    throw new Error("Invalid row number.");
  }

  const outputJsonPath = runtimeJsonPath(`apply-row-${rowNumber}`);

  const result = await runPowerShellScript({
    scriptName: "Update-AccessPoint.ps1",
    args: ["-RowNumber", String(rowNumber), "-ApplyMode", applyMode],
    outputJsonPath,
    showWindow,
    timeoutMs: 300_000,
  });

  try {
    const payload = readScriptPayload<OperationResult>(result, outputJsonPath);
    if (!payload.success) {
      throw new Error(payload.error ?? "Apply Changes failed.");
    }
    return payload;
  } finally {
    cleanupJsonFile(outputJsonPath);
  }
}

export interface LogFileInfo {
  filename: string;
  ip?: string;
  type?: string;
  createdAt: string;
  size: number;
}

export function listLogFiles(): LogFileInfo[] {
  if (!fs.existsSync(LOGS_DIR)) return [];

  return fs
    .readdirSync(LOGS_DIR)
    .filter((f) => f.endsWith(".log"))
    .map((filename) => {
      const fullPath = path.join(LOGS_DIR, filename);
      const stat = fs.statSync(fullPath);
      const ipMatch = filename.match(/(?:Clients|Update)_([\d_]+)_/);
      const type = filename.startsWith("Clients_") ? "Clients" : filename.startsWith("Update_") ? "Update" : "Other";

      return {
        filename,
        ip: ipMatch?.[1]?.replace(/_/g, "."),
        type,
        createdAt: stat.mtime.toISOString(),
        size: stat.size,
      };
    })
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
}

export function readLogFile(filename: string): string {
  if (!/^[\w.-]+\.log$/.test(filename)) {
    throw new Error("Invalid log filename.");
  }

  const fullPath = path.join(LOGS_DIR, filename);
  if (!fs.existsSync(fullPath)) {
    throw new Error("Log file not found.");
  }

  const resolved = fs.realpathSync(fullPath);
  const logsResolved = fs.realpathSync(LOGS_DIR);
  if (!resolved.startsWith(logsResolved)) {
    throw new Error("Path traversal detected.");
  }

  return fs.readFileSync(resolved, "utf8");
}

export function listBackupFiles() {
  if (!fs.existsSync(BACKUPS_DIR)) return [];

  return fs
    .readdirSync(BACKUPS_DIR)
    .filter((f) => f.endsWith(".txt"))
    .map((filename) => {
      const fullPath = path.join(BACKUPS_DIR, filename);
      const stat = fs.statSync(fullPath);
      return {
        filename,
        createdAt: stat.mtime.toISOString(),
        size: stat.size,
      };
    })
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
}

export function deleteOldLogs(olderThanHours: number): number {
  const cutoff = Date.now() - olderThanHours * 60 * 60 * 1000;
  let deleted = 0;

  for (const file of listLogFiles()) {
    if (new Date(file.createdAt).getTime() < cutoff) {
      fs.unlinkSync(path.join(LOGS_DIR, file.filename));
      deleted++;
    }
  }

  return deleted;
}
