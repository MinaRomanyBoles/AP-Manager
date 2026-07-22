import crypto from "node:crypto";
import type { NextFunction, Request, Response } from "express";

const tokens = new Map<string, number>();
const TOKEN_TTL_MS = 8 * 60 * 60 * 1000;

export function issueCsrfToken(): string {
  const token = crypto.randomBytes(32).toString("hex");
  tokens.set(token, Date.now() + TOKEN_TTL_MS);
  return token;
}

export function csrfProtection(req: Request, res: Response, next: NextFunction) {
  if (req.method === "GET" || req.method === "HEAD" || req.method === "OPTIONS") {
    return next();
  }

  const token = req.header("x-csrf-token") ?? req.body?.csrfToken;
  if (!token || typeof token !== "string") {
    return res.status(403).json({ success: false, error: "Missing CSRF token." });
  }

  const expiry = tokens.get(token);
  if (!expiry || expiry < Date.now()) {
    tokens.delete(token as string);
    return res.status(403).json({ success: false, error: "Invalid or expired CSRF token." });
  }

  return next();
}

export function settingsMiddleware(req: Request, _res: Response, next: NextFunction) {
  const settingsPath = req.app.get("settingsPath") as string | undefined;
  if (settingsPath) {
    try {
      const fs = require("node:fs");
      if (fs.existsSync(settingsPath)) {
        req.appSettings = JSON.parse(fs.readFileSync(settingsPath, "utf8"));
      }
    } catch {
      req.appSettings = { showPowerShellWindow: false };
    }
  } else {
    req.appSettings = { showPowerShellWindow: false };
  }
  next();
}

declare global {
  namespace Express {
    interface Request {
      appSettings?: { showPowerShellWindow?: boolean };
    }
  }
}
