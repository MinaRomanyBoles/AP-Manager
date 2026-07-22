import type { NextFunction, Request, Response } from "express";
import { isValidIp, isValidRowNumber } from "../services/accessPoints.js";

export function validateRowParam(req: Request, res: Response, next: NextFunction) {
  const row = Number(req.params.row);
  if (!isValidRowNumber(row)) {
    return res.status(400).json({ error: "Invalid row number." });
  }
  req.params.row = String(row);
  return next();
}

export function validateOpenApBody(req: Request, res: Response, next: NextFunction) {
  const ip = req.body?.ip;
  if (!ip || typeof ip !== "string" || !isValidIp(ip)) {
    return res.status(400).json({ error: "Valid IP address is required." });
  }
  return next();
}

export function validateSelectedRows(req: Request, res: Response, next: NextFunction) {
  const rows = req.body?.rows;
  if (!Array.isArray(rows) || rows.length === 0) {
    return res.status(400).json({ error: "At least one row must be selected." });
  }

  for (const row of rows) {
    if (!isValidRowNumber(Number(row))) {
      return res.status(400).json({ error: `Invalid row number: ${row}` });
    }
  }

  return next();
}
