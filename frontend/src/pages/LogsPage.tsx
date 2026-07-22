import { useEffect, useState } from "react";
import { api } from "../api/client";
import { useLanguage } from "../context/LanguageContext";
import { useToast } from "../context/ToastContext";

export function LogsPage({ onBack }: { onBack: () => void }) {
  const { t } = useLanguage();
  const { showToast } = useToast();
  const [logs, setLogs] = useState<Array<{ filename: string; ip?: string; type?: string; createdAt: string; size: number }>>([]);
  const [search, setSearch] = useState("");
  const [ipFilter, setIpFilter] = useState("");
  const [selectedLog, setSelectedLog] = useState<string | null>(null);
  const [content, setContent] = useState("");

  const loadLogs = async () => {
    try {
      const data = await api.getLogs();
      setLogs(data.logs);
    } catch (error) {
      showToast("error", (error as Error).message);
    }
  };

  useEffect(() => {
    void loadLogs();
  }, []);

  const filtered = logs.filter((log) => {
    const matchSearch = !search || log.filename.toLowerCase().includes(search.toLowerCase());
    const matchIp = !ipFilter || (log.ip ?? "").includes(ipFilter);
    return matchSearch && matchIp;
  });

  const openLog = async (filename: string) => {
    try {
      const data = await api.getLogContent(filename);
      setSelectedLog(filename);
      setContent(data.content);
    } catch (error) {
      showToast("error", (error as Error).message);
    }
  };

  const downloadLog = (filename: string) => {
    window.open(`/api/logs/${encodeURIComponent(filename)}/download`, "_blank");
  };

  const clearOld = async () => {
    const confirm = window.confirm(t("clearLogsConfirm"));
    if (!confirm) return;
    try {
      const result = await api.clearOldLogs(24, true);
      showToast("success", t("toastLogsDeleted", { count: result.deleted }));
      await loadLogs();
    } catch (error) {
      showToast("error", (error as Error).message);
    }
  };

  return (
    <div className="mx-auto max-w-[1600px] px-4 py-6">
      <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
        <button className="btn-secondary" onClick={onBack}>
          {t("backToDashboard")}
        </button>
        <button className="btn-danger" onClick={clearOld}>
          {t("clearOldLogs")}
        </button>
      </div>

      <div className="card p-4 md:p-6">
        <h2 className="mb-4 text-xl font-bold">{t("operationLogs")}</h2>
        <div className="mb-4 flex flex-wrap gap-2">
          <input className="input max-w-xs" placeholder={t("searchLogs")} value={search} onChange={(e) => setSearch(e.target.value)} />
          <input className="input max-w-xs" placeholder={t("filterByIp")} value={ipFilter} onChange={(e) => setIpFilter(e.target.value)} />
        </div>

        <div className="grid gap-4 lg:grid-cols-2">
          <div className="table-wrap max-h-[480px] overflow-auto">
            <table className="data-table">
              <thead>
                <tr>
                  <th>{t("filename")}</th>
                  <th>{t("ip")}</th>
                  <th>{t("type")}</th>
                  <th>{t("actions")}</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((log) => (
                  <tr key={log.filename}>
                    <td className="text-xs">{log.filename}</td>
                    <td>{log.ip ?? t("empty")}</td>
                    <td>{log.type ?? t("empty")}</td>
                    <td>
                      <div className="flex gap-1">
                        <button className="btn-secondary px-2 py-1 text-xs" onClick={() => openLog(log.filename)}>
                          {t("view")}
                        </button>
                        <button className="btn-secondary px-2 py-1 text-xs" onClick={() => downloadLog(log.filename)}>
                          {t("download")}
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div className="rounded-xl border border-slate-200 p-4 dark:border-slate-700">
            <h3 className="mb-2 font-semibold">{selectedLog ?? t("selectLog")}</h3>
            <pre className="max-h-[420px] overflow-auto whitespace-pre-wrap text-xs">{content || t("noLogSelected")}</pre>
          </div>
        </div>
      </div>
    </div>
  );
}
