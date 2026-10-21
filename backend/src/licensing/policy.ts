export const PRODUCT = "AP-Manager";
export const TRIAL_START = "2026-10-20T21:00:00.000Z";
// Inclusive through 25 October in Africa/Cairo (UTC+03:00 on this date).
export const TRIAL_EXPIRES_AT = "2026-10-25T21:00:00.000Z";
export const CLOCK_TOLERANCE_MS = 5 * 60_000;

export interface LicensePayload {
  version: 1;
  product: typeof PRODUCT;
  machineId: string;
  customer: string;
  issuedAt: string;
  expiresAt: string;
}

export interface LicenseStatus {
  allowed: boolean;
  reason: "trial" | "activated" | "expired" | "clock_rollback" | "state_error";
  machineId: string;
  expiresAt: string;
  timeZone: "Africa/Cairo";
  customer?: string;
  error?: string;
}
