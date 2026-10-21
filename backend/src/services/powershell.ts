import { spawn, type ChildProcess } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { ALLOWED_SCRIPTS, COMMAND_TIMEOUT_MS, PROJECT_ROOT, RUNTIME_DIR, SCRIPTS_DIR } from "../config.js";
import { assertClientLicense } from "../licensing/manager.js";
import { packaged, preparePowerShellPayload } from "../packagedAssets.js";

export interface PowerShellResult {
  exitCode: number;
  stdout: string;
  stderr: string;
  json?: unknown;
}

export interface RunScriptOptions {
  scriptName: string;
  args: string[];
  timeoutMs?: number;
  showWindow?: boolean;
  outputJsonPath?: string;
}

function sanitizeArg(value: string): string {
  if (/[\r\n\0]/.test(value)) {
    throw new Error("Invalid argument contains control characters.");
  }
  return value;
}

export function runPowerShellScript(options: RunScriptOptions): Promise<PowerShellResult> {
  const { scriptName, args, timeoutMs = COMMAND_TIMEOUT_MS, showWindow = false, outputJsonPath } = options;

  // Also protects jobs that were queued before the expiry boundary.
  assertClientLicense();

  if (!ALLOWED_SCRIPTS.has(scriptName)) {
    return Promise.reject(new Error(`Script '${scriptName}' is not allowed.`));
  }

  const scriptPath = path.join(SCRIPTS_DIR, scriptName);
  if (!packaged && !fs.existsSync(scriptPath)) {
    return Promise.reject(new Error(`Script not found: ${scriptName}`));
  }

  fs.mkdirSync(RUNTIME_DIR, { recursive: true });

  const sanitizedArgs = args.map((arg) => sanitizeArg(String(arg)));
  let psArgs = [
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    scriptPath,
    ...sanitizedArgs,
  ];

  if (outputJsonPath) {
    psArgs.push("-OutputJsonPath", outputJsonPath);
  }

  const payload = packaged ? preparePowerShellPayload(scriptName, sanitizedArgs, outputJsonPath) : undefined;
  if (packaged) {
    psArgs = ["-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command",
      "$s=[Console]::In.ReadToEnd(); & ([ScriptBlock]::Create($s))"];
  }

  return new Promise((resolve, reject) => {
    let stdout = "";
    let stderr = "";
    let settled = false;

    const psExe = packaged ? path.join(process.env.SystemRoot ?? "C:\\Windows", "System32", "WindowsPowerShell", "v1.0", "powershell.exe") : "powershell.exe";
    const child: ChildProcess = spawn(psExe, psArgs, {
      windowsHide: !showWindow,
      cwd: PROJECT_ROOT,
      stdio: [payload ? "pipe" : "ignore", "pipe", "pipe"],
    });
    if (payload) {
      child.stdin?.on("error", () => { /* Spawn/close handlers report the failure. */ });
      child.stdin?.end(payload, "utf8");
    }

    const timer = setTimeout(() => {
      if (!settled) {
        settled = true;
        child.kill();
        reject(new Error(`PowerShell script timed out after ${timeoutMs}ms.`));
      }
    }, timeoutMs);

    child.stdout?.on("data", (chunk: Buffer) => {
      stdout += chunk.toString("utf8");
    });

    child.stderr?.on("data", (chunk: Buffer) => {
      stderr += chunk.toString("utf8");
    });

    child.on("error", (error) => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        reject(error);
      }
    });

    child.on("close", (code) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);

      const exitCode = code ?? 1;
      let json: unknown;

      if (outputJsonPath && fs.existsSync(outputJsonPath)) {
        try {
          const raw = fs.readFileSync(outputJsonPath, "utf8").replace(/^\uFEFF/, "");
          json = JSON.parse(raw);
        } catch {
          // fall through
        }
      } else {
        const trimmed = stdout.trim().replace(/^\uFEFF/, "");
        const jsonStart = trimmed.indexOf("{");
        const jsonText = jsonStart >= 0 ? trimmed.slice(jsonStart) : trimmed;
        if (jsonText.startsWith("{")) {
          try {
            json = JSON.parse(jsonText);
          } catch {
            // ignore
          }
        }
      }

      resolve({ exitCode, stdout, stderr, json });
    });
  });
}

export function redactSecrets(text: string): string {
  return text
    .replace(/("AccessPassword"\s*:\s*")[^"]*(")/gi, '$1***$2')
    .replace(/("NewWiFiPassword"\s*:\s*")[^"]*(")/gi, '$1***$2')
    .replace(/wpa-psk ascii \S+/gi, "wpa-psk ascii ********")
    .replace(/Password:\s*\S+/gi, "Password: ********");
}
