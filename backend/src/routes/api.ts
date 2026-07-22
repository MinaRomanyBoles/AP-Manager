import { Router } from "express";
import {
  applyChangesForRow,
  deleteOldLogs,
  getClientsForRow,
  listBackupFiles,
  listLogFiles,
  loadAccessPoints,
  readLogFile,
} from "../services/accessPoints.js";
import {
  getApplyQueue,
  getClientsQueue,
  resetApplyQueue,
  resetClientsQueue,
} from "../services/jobQueue.js";
import { csrfProtection } from "../middleware/csrf.js";
import { validateOpenApBody, validateRowParam, validateSelectedRows } from "../middleware/validation.js";

const router = Router();

let lastExcelSync: string | null = null;
let showPowerShellWindow = false;

export function setShowPowerShellWindow(value: boolean) {
  showPowerShellWindow = value;
}

router.get("/health", (_req, res) => {
  res.json({
    status: "online",
    lastExcelSync,
    showPowerShellWindow,
  });
});

router.get("/csrf-token", (_req, res) => {
  res.status(404).json({ error: "Use /api/csrf-token" });
});

router.get("/access-points", async (_req, res) => {
  try {
    const data = await loadAccessPoints();
    if (data.success && data.lastSync) {
      lastExcelSync = data.lastSync;
    }
    res.json(data);
  } catch (error) {
    res.status(500).json({ success: false, error: (error as Error).message });
  }
});

router.post("/access-points/reload", csrfProtection, async (_req, res) => {
  try {
    const data = await loadAccessPoints();
    if (data.success && data.lastSync) {
      lastExcelSync = data.lastSync;
    }
    res.json(data);
  } catch (error) {
    res.status(500).json({ success: false, error: (error as Error).message });
  }
});

router.post("/access-points/:row/get-clients", csrfProtection, validateRowParam, async (req, res) => {
  try {
    const row = Number(req.params.row);
    const result = await getClientsForRow(row, showPowerShellWindow);
    res.json(result);
  } catch (error) {
    res.status(500).json({ success: false, error: (error as Error).message });
  }
});

router.post("/access-points/get-clients-all", csrfProtection, async (req, res) => {
  try {
    const data = await loadAccessPoints();
    if (!data.success || !data.accessPoints) {
      return res.status(400).json({ error: data.error ?? "Could not load access points." });
    }

    resetClientsQueue();
    const queue = getClientsQueue(async (rowNumber) => getClientsForRow(rowNumber, showPowerShellWindow));
    queue.reset();

    const rows = data.accessPoints.map((ap) => ap.rowNumber);
    for (const row of rows) {
      queue.add(`clients-${row}`, row);
    }

    res.json({ success: true, total: rows.length, message: "Refresh All Clients started." });
  } catch (error) {
    res.status(500).json({ success: false, error: (error as Error).message });
  }
});

router.get("/access-points/get-clients-all/status", (_req, res) => {
  const queue = getClientsQueue(async () => ({}));
  res.json(queue.getStatus());
});

router.post("/access-points/get-clients-all/cancel", csrfProtection, (_req, res) => {
  const queue = getClientsQueue(async () => ({}));
  queue.cancel();
  res.json({ success: true, message: "Cancellation requested." });
});

router.post("/access-points/:row/apply", csrfProtection, validateRowParam, async (req, res) => {
  try {
    const row = Number(req.params.row);
    const mode = (req.body?.mode as "all" | "ssid" | "password") ?? "all";
    const result = await applyChangesForRow(row, mode, showPowerShellWindow);
    res.json(result);
  } catch (error) {
    res.status(500).json({ success: false, error: (error as Error).message });
  }
});

router.post("/access-points/apply-selected", csrfProtection, validateSelectedRows, async (req, res) => {
  try {
    const rows = req.body.rows as number[];
    const mode = (req.body?.mode as "all" | "ssid" | "password") ?? "all";

    resetApplyQueue();
    const queue = getApplyQueue(async (job) => applyChangesForRow(job.rowNumber, job.mode, showPowerShellWindow));
    queue.reset();

    for (const row of rows) {
      queue.add(`apply-${row}`, { rowNumber: row, mode });
    }

    res.json({ success: true, total: rows.length, message: "Bulk apply started (one AP at a time)." });
  } catch (error) {
    res.status(500).json({ success: false, error: (error as Error).message });
  }
});

router.get("/access-points/apply-selected/status", (_req, res) => {
  const queue = getApplyQueue(async () => ({}));
  res.json(queue.getStatus());
});

router.post("/access-points/apply-selected/cancel", csrfProtection, (_req, res) => {
  const queue = getApplyQueue(async () => ({}));
  queue.cancel();
  res.json({ success: true });
});

router.get("/logs", (_req, res) => {
  res.json({ logs: listLogFiles() });
});

router.get("/logs/:filename", (req, res) => {
  try {
    const content = readLogFile(req.params.filename);
    res.json({ filename: req.params.filename, content });
  } catch (error) {
    res.status(404).json({ error: (error as Error).message });
  }
});

router.get("/logs/:filename/download", (req, res) => {
  try {
    const content = readLogFile(req.params.filename);
    res.setHeader("Content-Disposition", `attachment; filename="${req.params.filename}"`);
    res.type("text/plain").send(content);
  } catch (error) {
    res.status(404).json({ error: (error as Error).message });
  }
});

router.post("/logs/clear-old", csrfProtection, (req, res) => {
  const hours = Number(req.body?.olderThanHours ?? 24);
  const confirm = req.body?.confirm === true;

  if (hours < 24 && !confirm) {
    return res.status(400).json({
      error: "Deleting logs newer than 24 hours requires confirm: true.",
      requiresConfirmation: true,
    });
  }

  const deleted = deleteOldLogs(hours);
  res.json({ success: true, deleted });
});

router.get("/backups", (_req, res) => {
  res.json({ backups: listBackupFiles() });
});

router.post("/open-ap", csrfProtection, validateOpenApBody, (req, res) => {
  const ip = req.body.ip as string;
  res.json({ url: `http://${ip}`, httpsUrl: `https://${ip}` });
});

router.post("/settings/powershell-window", csrfProtection, (req, res) => {
  showPowerShellWindow = Boolean(req.body?.show);
  res.json({ showPowerShellWindow });
});

export default router;
