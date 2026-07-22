import cookieParser from "cookie-parser";
import cors from "cors";
import express from "express";
import rateLimit from "express-rate-limit";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { HOST, LOGO_PATH, PORT, PROJECT_ROOT } from "./config.js";
import { cleanupCsrfTokens, issueCsrfToken } from "./middleware/csrf.js";
import apiRouter from "./routes/api.js";

const __filename = fileURLToPath(import.meta.url);

const app = express();

app.set("trust proxy", 1);

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

app.use("/api", apiRouter);

app.get("/logo.png", (_req, res) => {
  if (fs.existsSync(LOGO_PATH)) {
    res.sendFile(LOGO_PATH);
  } else {
    res.status(404).send("Logo not found");
  }
});

const frontendDist = path.join(PROJECT_ROOT, "frontend", "dist");
if (fs.existsSync(frontendDist)) {
  app.use(express.static(frontendDist));
  app.get("*", (req, res, next) => {
    if (req.path.startsWith("/api")) return next();
    res.sendFile(path.join(frontendDist, "index.html"));
  });
}

app.use((err: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  res.status(500).json({ error: err.message });
});

setInterval(cleanupCsrfTokens, 30 * 60 * 1000);

export function startServer() {
  return app.listen(PORT, HOST, () => {
    console.log(`AP Manager backend running at http://${HOST}:${PORT}`);
  });
}

if (process.argv[1] && path.resolve(process.argv[1]) === __filename) {
  startServer();
}

export default app;
