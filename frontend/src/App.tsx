import { useCallback, useEffect, useState } from "react";
import { api, type AccessPoint } from "./api/client";
import { AccessPointTable } from "./components/AccessPointTable";
import { Header } from "./components/Header";
import { ConfirmModal, ErrorModal, ResultModal } from "./components/Modals";
import { SummaryCards } from "./components/SummaryCards";
import { useLanguage } from "./context/LanguageContext";
import { useTheme } from "./context/ThemeContext";
import { useToast } from "./context/ToastContext";
import { LogsPage } from "./pages/LogsPage";

type View = "dashboard" | "logs";

export default function App() {
  const { toggleTheme } = useTheme();
  const { showToast } = useToast();
  const { t } = useLanguage();

  const [view, setView] = useState<View>("dashboard");
  const [accessPoints, setAccessPoints] = useState<AccessPoint[]>([]);
  const [lastExcelSync, setLastExcelSync] = useState<string | null>(null);
  const [backendOnline, setBackendOnline] = useState(false);
  const [lastUpdated, setLastUpdated] = useState<string | null>(null);
  const [selectedRows, setSelectedRows] = useState<Set<number>>(new Set());
  const [rowLoading, setRowLoading] = useState<Record<number, string | null>>({});
  const [rowStage, setRowStage] = useState<Record<number, string>>({});
  const [refreshingAll, setRefreshingAll] = useState(false);
  const [refreshProgress, setRefreshProgress] = useState<{ completed: number; total: number } | null>(null);
  const [showPsWindow, setShowPsWindow] = useState(false);
  const [errorModal, setErrorModal] = useState<string | null>(null);
  const [resultModal, setResultModal] = useState<Record<string, unknown> | null>(null);
  const [confirmModal, setConfirmModal] = useState<{
    action: string;
    rows: number[];
    mode?: "all" | "ssid" | "password";
  } | null>(null);

  const loadData = useCallback(async () => {
    try {
      const health = await api.health();
      setBackendOnline(health.status === "online");
      setLastUpdated(new Date().toISOString());

      const data = await api.getAccessPoints();
      if (!data.success) throw new Error(data.error ?? t("toastLoadFailed"));
      setAccessPoints(data.accessPoints ?? []);
      setLastExcelSync(data.lastSync ?? null);
    } catch (error) {
      setBackendOnline(false);
      showToast("error", (error as Error).message);
    }
  }, [showToast, t]);

  useEffect(() => {
    void loadData();
    const interval = setInterval(() => void loadData(), 60_000);
    return () => clearInterval(interval);
  }, [loadData]);

  const updateRow = (rowNumber: number, patch: Partial<AccessPoint>) => {
    setAccessPoints((prev) => prev.map((ap) => (ap.rowNumber === rowNumber ? { ...ap, ...patch } : ap)));
  };

  const setRowBusy = (row: number, busy: boolean, stage?: string) => {
    setRowLoading((prev) => ({ ...prev, [row]: busy ? stage ?? t("stageWorking") : null }));
    if (stage) setRowStage((prev) => ({ ...prev, [row]: stage }));
  };

  const handleGetClients = async (row: number) => {
    setRowBusy(row, true, t("stageConnecting"));
    updateRow(row, { clients: "..." });

    try {
      setRowStage((prev) => ({ ...prev, [row]: t("stageReadingClients") }));
      const result = await api.getClients(row);
      updateRow(row, {
        clients: result.clients ?? 0,
        lastUpdated: result.lastUpdated ?? new Date().toLocaleString(),
        connectionStatus: "Online",
      });
      showToast("success", t("toastClientsUpdated", { row }));
    } catch (error) {
      updateRow(row, { clients: "ERROR", connectionStatus: "Error" });
      setErrorModal((error as Error).message);
    } finally {
      setRowBusy(row, false);
    }
  };

  const handleApply = async (row: number) => {
    setRowBusy(row, true, t("stageCreatingBackup"));
    try {
      setRowStage((prev) => ({ ...prev, [row]: t("stageUpdatingSsid") }));
      const result = await api.applyChanges(row, "all");
      setResultModal(result);
      await loadData();
      showToast("success", t("toastChangesApplied", { row }));
    } catch (error) {
      setErrorModal((error as Error).message);
    } finally {
      setRowBusy(row, false);
    }
  };

  const handleRefreshAll = async () => {
    setRefreshingAll(true);
    try {
      const start = await api.refreshAllClients();
      setRefreshProgress({ completed: 0, total: start.total });

      const poll = setInterval(async () => {
        const status = await api.refreshAllStatus();
        setRefreshProgress({ completed: status.completed, total: status.total });

        if (status.completed >= status.total) {
          clearInterval(poll);
          setRefreshingAll(false);
          setRefreshProgress(null);
          await loadData();
          showToast("success", t("toastRefreshComplete"));
        }
      }, 2000);
    } catch (error) {
      setRefreshingAll(false);
      setRefreshProgress(null);
      showToast("error", (error as Error).message);
    }
  };

  const cancelRefreshAll = async () => {
    try {
      await api.cancelRefreshAll();
      setRefreshingAll(false);
      setRefreshProgress(null);
      showToast("info", t("toastRefreshCancelled"));
    } catch (error) {
      showToast("error", (error as Error).message);
    }
  };

  const handleBulkAction = (action: string) => {
    const rows = Array.from(selectedRows);
    const devices = accessPoints
      .filter((ap) => selectedRows.has(ap.rowNumber))
      .map((ap) => ({ name: ap.accessPointName, ip: ap.accessPointIP }));

    if (action === "export") {
      const selected = accessPoints.filter((ap) => selectedRows.has(ap.rowNumber));
      const blob = new Blob([JSON.stringify(selected, null, 2)], { type: "application/json" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = "selected-access-points.json";
      a.click();
      URL.revokeObjectURL(url);
      return;
    }

    if (action === "open-ap") {
      for (const ap of devices) {
        window.open(`http://${ap.ip}`, "_blank");
      }
      return;
    }

    if (action === "get-clients") {
      void (async () => {
        for (const row of rows) {
          await handleGetClients(row);
        }
      })();
      return;
    }

    const mode = action === "apply-ssid" ? "ssid" : action === "apply-password" ? "password" : "all";
    setConfirmModal({ action, rows, mode });
  };

  const executeConfirmedBulk = async () => {
    if (!confirmModal) return;
    const { rows, mode = "all" } = confirmModal;
    setConfirmModal(null);

    try {
      await api.applySelected(rows, mode);
      showToast("info", t("toastBulkStarted", { count: rows.length }));
    } catch (error) {
      showToast("error", (error as Error).message);
    }
  };

  const handleOpenAp = (ip: string) => {
    window.open(`http://${ip}`, "_blank");
  };

  if (view === "logs") {
    return <LogsPage onBack={() => setView("dashboard")} />;
  }

  return (
    <div className="mx-auto max-w-[1600px] px-4 py-6">
      <Header
        backendOnline={backendOnline}
        lastUpdated={lastUpdated}
        onReloadExcel={async () => {
          try {
            const data = await api.reloadExcel();
            setAccessPoints(data.accessPoints ?? []);
            setLastExcelSync(data.lastSync ?? null);
            showToast("success", t("toastExcelReloaded"));
          } catch (error) {
            showToast("error", (error as Error).message);
          }
        }}
        onRefreshAll={handleRefreshAll}
        refreshing={refreshingAll}
        onNavigateLogs={() => setView("logs")}
        onToggleTheme={toggleTheme}
        showPsWindow={showPsWindow}
        onTogglePsWindow={async (show) => {
          setShowPsWindow(show);
          await api.setPowerShellWindow(show);
        }}
      />

      <div className="mb-6">
        <SummaryCards accessPoints={accessPoints} lastExcelSync={lastExcelSync} />
      </div>

      {refreshProgress && (
        <div className="card mb-4 p-4">
          <div className="mb-2 flex items-center justify-between text-sm">
            <span>
              {t("refreshProgress")}: {refreshProgress.completed} / {refreshProgress.total} {t("completed")}
            </span>
            <button className="btn-danger px-3 py-1 text-xs" onClick={cancelRefreshAll}>
              {t("cancel")}
            </button>
          </div>
          <div className="h-2 overflow-hidden rounded-full bg-slate-200 dark:bg-slate-700">
            <div
              className="h-full bg-cisco-blue transition-all"
              style={{ width: `${(refreshProgress.completed / refreshProgress.total) * 100}%` }}
            />
          </div>
        </div>
      )}

      <AccessPointTable
        accessPoints={accessPoints}
        selectedRows={selectedRows}
        onSelectionChange={setSelectedRows}
        rowLoading={rowLoading}
        rowStage={rowStage}
        onGetClients={handleGetClients}
        onApply={handleApply}
        onOpenAp={handleOpenAp}
        onBulkAction={handleBulkAction}
      />

      {errorModal && (
        <ErrorModal title={t("operationFailed")} message={errorModal} onClose={() => setErrorModal(null)} />
      )}

      {resultModal && (
        <ResultModal title={t("applySuccess")} details={resultModal} onClose={() => setResultModal(null)} />
      )}

      {confirmModal && (
        <ConfirmModal
          title={t("confirmBulkTitle")}
          devices={accessPoints
            .filter((ap) => confirmModal.rows.includes(ap.rowNumber))
            .map((ap) => ({ name: ap.accessPointName, ip: ap.accessPointIP }))}
          onConfirm={executeConfirmedBulk}
          onClose={() => setConfirmModal(null)}
        />
      )}
    </div>
  );
}
