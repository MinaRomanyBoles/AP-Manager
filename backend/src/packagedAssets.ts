import { getAsset, isSea } from "node:sea";
import path from "node:path";

export const packaged = isSea();

export function assetText(key: string): string {
  return getAsset(key, "utf8");
}

export function servePackagedAsset(urlPath: string): { data: Buffer; type: string } | undefined {
  if (!packaged) return undefined;
  const key = urlPath === "/" ? "frontend/index.html" : `frontend${urlPath}`;
  try {
    const types: Record<string, string> = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8", ".png": "image/png", ".svg": "image/svg+xml", ".ico": "image/x-icon" };
    return { data: Buffer.from(getAsset(key)), type: types[path.extname(key)] ?? "application/octet-stream" };
  } catch { return undefined; }
}

// Each original script remains a param() block, called in one PowerShell process.
// Helpers are dot-sourced from in-memory ScriptBlocks; no .ps1 files are written.
export function preparePowerShellPayload(scriptName: string, args: string[], outputJsonPath?: string): string {
  const read = (name: string) => assetText(`powershell/${name}`).replace(/^\uFEFF/, "")
    .replace(/^\. \(Join-Path \$PSScriptRoot "[^"]+"\)\s*$/gm, "");
  const helpers = ["Json-Helper.ps1", "Cisco-Common.ps1", "Excel-Helper.ps1", "AP-Manager-Core.ps1"];
  const encoded = (text: string) => Buffer.from(text, "utf8").toString("base64");
  const lines = [
    "$ErrorActionPreference = 'Stop'",
    "[Console]::OutputEncoding = [Text.Encoding]::UTF8",
    "function Decode-APAsset([string]$b) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b)) }",
    ...helpers.map(name => `. ([ScriptBlock]::Create((Decode-APAsset '${encoded(read(name))}')))`),
    // The working directory is the EXE directory, supplied by spawn(cwd).
    "function Get-ProjectRoot { return [Environment]::CurrentDirectory }",
    "$apParams = @{}",
  ];
  const allArgs = outputJsonPath ? [...args, "-OutputJsonPath", outputJsonPath] : args;
  for (let i = 0; i < allArgs.length; i += 2) {
    const key = allArgs[i].replace(/^-/, "");
    if (!["RowNumber", "ApplyMode", "OutputJsonPath"].includes(key) || allArgs[i + 1] === undefined) throw new Error("Invalid packaged script parameters.");
    lines.push(`$apParams['${key}'] = Decode-APAsset '${encoded(allArgs[i + 1])}'`);
  }
  lines.push(`& ([ScriptBlock]::Create((Decode-APAsset '${encoded(read(scriptName))}'))) @apParams`);
  return lines.join("\n");
}
