import crypto from "node:crypto";
import type { NextFunction, Request, Response } from "express";

const csrfTokens = new Map<string, number>();
const TOKEN_TTL_MS = 4 * 60 * 60 * 1000;

export function issueCsrfToken(): string {
  const token = crypto.randomBytes(32).toString("hex");
  csrfTokens.set(token, Date.now() + TOKEN_TTL_MS);
  return token;
}

export function csrfProtection(req: Request, res: Response, next: NextFunction) {
  if (["GET", "HEAD", "OPTIONS"].includes(req.method)) {
    return next();
  }

  const token = req.header("x-csrf-token") ?? req.body?.csrfToken;
  if (!token || typeof token !== "string") {
    return res.status(403).json({ error: "CSRF token missing." });
  }

  const expiry = csrfTokens.get(token);
  if (!expiry || expiry < Date.now()) {
    csrfTokens.delete(token);
    return res.status(403).json({ error: "CSRF token invalid or expired." });
  }

  return next();
}

export function cleanupCsrfTokens() {
  const now = Date.now();
  for (const [token, expiry] of csrfTokens.entries()) {
    if (expiry < now) csrfTokens.delete(token);
  }
}
