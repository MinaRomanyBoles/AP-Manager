import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export const PROJECT_ROOT = path.resolve(__dirname, "..", "..");
export const SCRIPTS_DIR = path.join(PROJECT_ROOT, "Scripts");
export const LOGS_DIR = path.join(PROJECT_ROOT, "Logs");
export const BACKUPS_DIR = path.join(PROJECT_ROOT, "Backups");
export const RUNTIME_DIR = path.join(PROJECT_ROOT, "Runtime");
export const EXCEL_PATH = path.join(PROJECT_ROOT, "AP-Info-Manager.xlsx");
export const LOGO_PATH = path.join(PROJECT_ROOT, "logo.png");

export const HOST = "127.0.0.1";
export const PORT = 8787;

export const ALLOWED_SCRIPTS = new Set([
  "Read-AccessPoints.ps1",
  "Get-Clients.ps1",
  "Update-AccessPoint.ps1",
]);

export const CONNECTION_TIMEOUT_MS = 10_000;
export const COMMAND_TIMEOUT_MS = 30_000;
export const RSA_TIMEOUT_MS = 90_000;

export const MAX_CONCURRENT_CLIENT_JOBS = 3;
export const MAX_CONCURRENT_APPLY_JOBS = 1;
