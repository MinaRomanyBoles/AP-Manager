import { useState } from "react";
import { useLanguage } from "../context/LanguageContext";

interface ErrorModalProps {
  title: string;
  message: string;
  onClose: () => void;
}

export function ErrorModal({ title, message, onClose }: ErrorModalProps) {
  const { t } = useLanguage();

  const copyError = async () => {
    await navigator.clipboard.writeText(message);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="card max-h-[80vh] w-full max-w-lg overflow-auto p-6">
        <h3 className="mb-2 text-lg font-semibold text-red-600">{title}</h3>
        <pre className="mb-4 whitespace-pre-wrap rounded-lg bg-slate-100 p-3 text-sm dark:bg-slate-800">{message}</pre>
        <div className="flex justify-end gap-2">
          <button className="btn-secondary" onClick={copyError}>
            {t("copyError")}
          </button>
          <button className="btn-primary" onClick={onClose}>
            {t("close")}
          </button>
        </div>
      </div>
    </div>
  );
}

interface ConfirmModalProps {
  title: string;
  devices: Array<{ name: string; ip: string }>;
  onConfirm: () => void;
  onClose: () => void;
}

export function ConfirmModal({ title, devices, onConfirm, onClose }: ConfirmModalProps) {
  const { t } = useLanguage();
  const [typed, setTyped] = useState("");

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="card max-h-[80vh] w-full max-w-lg overflow-auto p-6">
        <h3 className="mb-2 text-lg font-semibold">{title}</h3>
        <p className="mb-3 text-sm text-slate-600 dark:text-slate-300">
          {t("confirmBulkMessage")} <strong>{devices.length}</strong> {t("accessPointsWord")}:
        </p>
        <ul className="mb-4 max-h-40 overflow-auto rounded-lg bg-slate-100 p-3 text-sm dark:bg-slate-800">
          {devices.map((d) => (
            <li key={d.ip}>
              {d.name || t("unnamed")} — {d.ip}
            </li>
          ))}
        </ul>
        <p className="mb-2 text-sm">{t("typeApplyConfirm")}</p>
        <input className="input mb-4" value={typed} onChange={(e) => setTyped(e.target.value)} />
        <div className="flex justify-end gap-2">
          <button className="btn-secondary" onClick={onClose}>
            {t("cancel")}
          </button>
          <button className="btn-danger" disabled={typed !== "APPLY"} onClick={onConfirm}>
            {t("confirm")}
          </button>
        </div>
      </div>
    </div>
  );
}

interface ResultModalProps {
  title: string;
  details: Record<string, unknown>;
  onClose: () => void;
}

export function ResultModal({ title, details, onClose }: ResultModalProps) {
  const { t } = useLanguage();

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="card max-h-[80vh] w-full max-w-lg overflow-auto p-6">
        <h3 className="mb-4 text-lg font-semibold text-emerald-600">{title}</h3>
        <dl className="space-y-2 text-sm">
          {Object.entries(details).map(([key, value]) => (
            <div key={key} className="flex justify-between gap-4 border-b border-slate-100 py-1 dark:border-slate-800">
              <dt className="font-medium capitalize text-slate-500">{key.replace(/([A-Z])/g, " $1")}</dt>
              <dd className="text-right">{String(value ?? t("empty"))}</dd>
            </div>
          ))}
        </dl>
        <div className="mt-4 flex justify-end">
          <button className="btn-primary" onClick={onClose}>
            {t("close")}
          </button>
        </div>
      </div>
    </div>
  );
}
