import cookieParser from "cookie-parser";
import cors from "cors";
import express from "express";
import rateLimit from "express-rate-limit";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { HOST, LOGO_PATH, PORT, PROJECT_ROOT } from "./config.js";
import { cleanupCsrfTokens, csrfProtection, issueCsrfToken } from "./middleware/csrf.js";
import apiRouter from "./routes/api.js";
import { getClientLicense } from "./licensing/manager.js";
import { packaged, servePackagedAsset } from "./packagedAssets.js";

const __filename = fileURLToPath(import.meta.url);

const app = express();

app.set("trust proxy", false);
app.disable("x-powered-by");

// Local HTTP endpoints must not accept DNS-rebinding Host headers.
app.use((req, res, next) => {
  if (!/^(?:127\.0\.0\.1|localhost)(?::\d{1,5})?$/.test(req.headers.host ?? "")) {
    return res.status(403).json({ error: "Local access only." });
  }
  next();
});

app.use(
  cors({
    origin: [`http://${HOST}:${PORT}`, `http://127.0.0.1:${PORT}`],
    credentials: true,
  }),
);

app.use(express.json({ limit: "1mb" }));
app.use(cookieParser());

app.use(
  rateLimit({
    windowMs: 60_000,
    max: 120,
    standardHeaders: true,
    legacyHeaders: false,
  }),
);

app.get("/api/csrf-token", (_req, res) => {
  const token = issueCsrfToken();
  res.json({ csrfToken: token });
});

app.get("/api/license/status", (_req, res) => {
  res.setHeader("Cache-Control", "no-store");
  res.json(getClientLicense()?.status() ?? { allowed: true, reason: "development" });
});

app.post("/api/license/activate", csrfProtection, (req, res) => {
  const license = getClientLicense();
  if (!license) return res.status(400).json({ error: "Activation is available in the client edition." });
  if (typeof req.body?.token !== "string") return res.status(400).json({ error: "Enter an activation key." });
  try { res.json(license.activate(req.body.token)); }
  catch (error) { res.status(400).json({ error: (error as Error).message }); }
});

app.use("/api", (_req, res, next) => {
  const status = getClientLicense()?.status();
  if (status && !status.allowed) {
    return res.status(402).json({ error: status.error ?? "انتهت صلاحية النسخة. يرجى التفعيل. / Activation required.", code: "ACTIVATION_REQUIRED", license: status });
  }
  next();
});

app.use("/api", apiRouter);

app.get("/logo.png", (_req, res) => {
  if (packaged) {
    const logo = servePackagedAsset("/logo.png");
    if (logo) return res.type(logo.type).send(logo.data);
  }
  if (fs.existsSync(LOGO_PATH)) {
    res.sendFile(LOGO_PATH);
  } else {
    res.status(404).send("Logo not found");
  }
});

const frontendDist = path.join(PROJECT_ROOT, "frontend", "dist");
if (packaged) {
  app.get("*", (req, res) => {
    if (req.path.startsWith("/api")) return res.status(404).json({ error: "Not found." });
    const asset = servePackagedAsset(req.path) ?? (path.extname(req.path) ? undefined : servePackagedAsset("/"));
    if (!asset) return res.status(404).send("Not found");
    res.type(asset.type).send(asset.data);
  });
} else if (fs.existsSync(frontendDist)) {
  app.use(express.static(frontendDist));
  app.get("*", (req, res, next) => {
    if (req.path.startsWith("/api")) return next();
    res.sendFile(path.join(frontendDist, "index.html"));
  });
}

app.use((err: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  res.status(500).json({ error: err.message });
});

setInterval(cleanupCsrfTokens, 30 * 60 * 1000).unref();

export function startServer() {
  return app.listen(PORT, HOST, () => {
    console.log(`AP Manager backend running at http://${HOST}:${PORT}`);
  });
}

if (!packaged && process.argv[1] && path.resolve(process.argv[1]) === __filename) {
  startServer();
}

export default app;
