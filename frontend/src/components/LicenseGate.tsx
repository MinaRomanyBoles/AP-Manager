import { useCallback, useEffect, useState, type FormEvent, type ReactNode } from "react";
import { useLanguage } from "../context/LanguageContext";

interface Status {
  allowed: boolean;
  reason: string;
  machineId?: string;
  expiresAt?: string;
  error?: string;
}

export function LicenseGate({ children }: { children: ReactNode }) {
  const { language, toggleLanguage, dir } = useLanguage();
  const ar = language === "ar";
  const [status, setStatus] = useState<Status | null>(null);
  const [token, setToken] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [open, setOpen] = useState(false);
  const [copied, setCopied] = useState(false);

  const check = useCallback(async () => {
    try {
      const res = await fetch("/api/license/status", { cache: "no-store" });
      if (!res.ok) throw new Error("Could not check activation status.");
      setStatus(await res.json());
      setError("");
    } catch (e) {
      setError((e as Error).message);
      // Do not keep showing the dashboard after losing license verification.
      setStatus(null);
    }
  }, []);

  useEffect(() => {
    void check();
    const interval = setInterval(() => void check(), 20_000);
    const onBlocked = () => { void check(); };
    window.addEventListener("ap-activation-required", onBlocked);
    return () => { clearInterval(interval); window.removeEventListener("ap-activation-required", onBlocked); };
  }, [check]);

  // Switch the UI exactly at the displayed deadline, even without user actions.
  useEffect(() => {
    if (!status?.allowed || !status.expiresAt) return;
    const delay = Math.max(0, Date.parse(status.expiresAt) - Date.now());
    const timer = setTimeout(() => void check(), Math.min(delay + 50, 2_147_483_647));
    return () => clearTimeout(timer);
  }, [status, check]);

  async function activate(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError("");
    try {
      const csrfRes = await fetch("/api/csrf-token");
      const csrf = await csrfRes.json();
      const res = await fetch("/api/license/activate", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf.csrfToken },
        body: JSON.stringify({ token: token.trim() }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? "Activation failed.");
      setStatus(data);
      setToken("");
      setOpen(false);
    } catch (e) { setError((e as Error).message); }
    finally { setBusy(false); }
  }

  if (!status) return <main className="mx-auto max-w-lg p-8 text-center" dir={dir}>
    <h1 className="mb-4 text-2xl font-bold">AP Manager</h1>
    <p>{error || (ar ? "جارٍ التحقق من صلاحية النسخة…" : "Checking activation…")}</p>
    {error && <button className="btn-primary mt-4" onClick={() => void check()}>{ar ? "إعادة المحاولة" : "Retry"}</button>}
  </main>;

  const expiry = status.expiresAt ? new Intl.DateTimeFormat(ar ? "ar-EG" : "en-GB", {
    timeZone: "Africa/Cairo", dateStyle: "medium", timeStyle: "short",
  }).format(new Date(Date.parse(status.expiresAt) - 1)) : "";

  const activation = <section className="card mx-auto w-full max-w-2xl p-6 md:p-8" dir={dir}>
    <div className="mb-5 flex items-center justify-between gap-4">
      <h1 className="text-2xl font-bold">AP Manager</h1>
      <button className="btn-secondary" onClick={toggleLanguage}>{ar ? "English" : "العربية"}</button>
    </div>
    <h2 className="mb-3 text-xl font-semibold">{ar ? "تفعيل البرنامج" : "Software activation"}</h2>
    <p className="mb-4 text-slate-600 dark:text-slate-300">{status.allowed
      ? (ar ? "يمكنك تجديد الترخيص قبل انتهاء المدة." : "You can renew your license before it expires.")
      : (ar ? "انتهت صلاحية النسخة أو تعذر التحقق منها. تواصل مع مزوّد البرنامج للحصول على مفتاح التفعيل." : "This copy has expired or cannot be verified. Contact your software provider for an activation key.")}</p>
    {status.error && <p role="alert" className="mb-4 rounded-lg bg-amber-50 p-3 text-amber-900">{status.error}</p>}
    <label className="mb-2 block font-medium" htmlFor="machine-id">{ar ? "رقم الجهاز — أرسله لمزوّد البرنامج" : "Machine ID — send this to your software provider"}</label>
    <div className="mb-5 flex gap-2">
      <input id="machine-id" className="min-w-0 flex-1 rounded-lg border bg-slate-50 p-3 font-mono text-sm text-slate-900" dir="ltr" readOnly value={status.machineId ?? ""} />
      <button className="btn-secondary" onClick={async () => { try { await navigator.clipboard.writeText(status.machineId ?? ""); setCopied(true); } catch { setError(ar ? "انسخ رقم الجهاز يدويًا." : "Select and copy the machine ID manually."); } }}>{copied ? (ar ? "تم النسخ" : "Copied") : (ar ? "نسخ" : "Copy")}</button>
    </div>
    <form onSubmit={activate}>
      <label className="mb-2 block font-medium" htmlFor="activation-key">{ar ? "مفتاح التفعيل" : "Activation key"}</label>
      <textarea id="activation-key" dir="ltr" className="w-full rounded-lg border bg-slate-50 p-3 font-mono text-sm text-slate-900" rows={4} value={token} onChange={e => setToken(e.target.value)} required maxLength={8192} />
      {error && <p role="alert" className="my-3 text-red-600">{error}</p>}
      <div className="mt-4 flex gap-3">
        <button className="btn-primary" type="submit" disabled={busy || !token.trim()}>{busy ? (ar ? "جارٍ التفعيل…" : "Activating…") : (ar ? "تفعيل" : "Activate")}</button>
        {status.allowed && <button className="btn-secondary" type="button" onClick={() => setOpen(false)}>{ar ? "رجوع" : "Back"}</button>}
      </div>
    </form>
    {expiry && <p className="mt-5 text-sm text-slate-500">{ar ? "صالح حتى: " : "Valid through: "}{expiry} {ar ? "بتوقيت القاهرة" : "Cairo time"}</p>}
  </section>;

  if (!status.allowed || open) return <main className="min-h-screen bg-slate-100 p-4 pt-10 dark:bg-slate-950">{activation}</main>;
  return <>
    {status.reason !== "development" && <div className="flex flex-wrap items-center justify-center gap-3 bg-slate-900 px-4 py-2 text-sm text-white" dir={dir}>
      <span>{ar ? "صالح حتى " : "Valid through "}{expiry} {ar ? "بتوقيت القاهرة" : "Cairo time"}</span>
      <button className="rounded border border-slate-500 px-3 py-1" onClick={() => setOpen(true)}>{ar ? "تفعيل / تجديد" : "Activate / Renew"}</button>
    </div>}
    {children}
  </>;
}
