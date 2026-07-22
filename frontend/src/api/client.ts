export interface AccessPoint {
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

export interface QueueStatus {
  total: number;
  completed: number;
  running: number;
  pending: number;
  failed: number;
  cancelled: number;
}

let csrfToken: string | null = null;

async function ensureCsrfToken(): Promise<string> {
  if (csrfToken) return csrfToken;
  const res = await fetch("/api/csrf-token");
  const data = await res.json();
  csrfToken = data.csrfToken;
  return csrfToken!;
}

async function apiFetch<T>(url: string, options: RequestInit = {}): Promise<T> {
  const headers = new Headers(options.headers);
  if (options.method && !["GET", "HEAD"].includes(options.method)) {
    headers.set("X-CSRF-Token", await ensureCsrfToken());
  }
  if (!headers.has("Content-Type") && options.body) {
    headers.set("Content-Type", "application/json");
  }

  const res = await fetch(url, { ...options, headers });
  const data = await res.json().catch(() => ({}));

  if (!res.ok) {
    throw new Error(data.error ?? `Request failed (${res.status})`);
  }

  return data as T;
}

export const api = {
  health: () => apiFetch<{ status: string; lastExcelSync: string | null }>("/api/health"),

  getAccessPoints: () =>
    apiFetch<{ success: boolean; accessPoints?: AccessPoint[]; lastSync?: string; error?: string }>(
      "/api/access-points",
    ),

  reloadExcel: () =>
    apiFetch<{ success: boolean; accessPoints?: AccessPoint[]; lastSync?: string; error?: string }>(
      "/api/access-points/reload",
      { method: "POST", body: "{}" },
    ),

  getClients: (row: number) =>
    apiFetch<{ success: boolean; clients?: number; error?: string; lastUpdated?: string }>(
      `/api/access-points/${row}/get-clients`,
      { method: "POST", body: "{}" },
    ),

  refreshAllClients: () =>
    apiFetch<{ success: boolean; total: number }>("/api/access-points/get-clients-all", {
      method: "POST",
      body: "{}",
    }),

  refreshAllStatus: () => apiFetch<QueueStatus>("/api/access-points/get-clients-all/status"),

  cancelRefreshAll: () =>
    apiFetch<{ success: boolean }>("/api/access-points/get-clients-all/cancel", {
      method: "POST",
      body: "{}",
    }),

  applyChanges: (row: number, mode: "all" | "ssid" | "password" = "all") =>
    apiFetch<Record<string, unknown>>(`/api/access-points/${row}/apply`, {
      method: "POST",
      body: JSON.stringify({ mode }),
    }),

  applySelected: (rows: number[], mode: "all" | "ssid" | "password" = "all") =>
    apiFetch<{ success: boolean; total: number }>("/api/access-points/apply-selected", {
      method: "POST",
      body: JSON.stringify({ rows, mode }),
    }),

  applySelectedStatus: () => apiFetch<QueueStatus>("/api/access-points/apply-selected/status"),

  getLogs: () => apiFetch<{ logs: Array<{ filename: string; ip?: string; type?: string; createdAt: string; size: number }> }>("/api/logs"),

  getLogContent: (filename: string) =>
    apiFetch<{ filename: string; content: string }>(`/api/logs/${encodeURIComponent(filename)}`),

  clearOldLogs: (olderThanHours: number, confirm = false) =>
    apiFetch<{ success: boolean; deleted: number }>("/api/logs/clear-old", {
      method: "POST",
      body: JSON.stringify({ olderThanHours, confirm }),
    }),

  setPowerShellWindow: (show: boolean) =>
    apiFetch<{ showPowerShellWindow: boolean }>("/api/settings/powershell-window", {
      method: "POST",
      body: JSON.stringify({ show }),
    }),
};
