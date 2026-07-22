import { useLanguage } from "../context/LanguageContext";

interface HeaderProps {
  backendOnline: boolean;
  lastUpdated: string | null;
  onReloadExcel: () => void;
  onRefreshAll: () => void;
  refreshing: boolean;
  onNavigateLogs: () => void;
  onToggleTheme: () => void;
  showPsWindow: boolean;
  onTogglePsWindow: (v: boolean) => void;
}

export function Header({
  backendOnline,
  lastUpdated,
  onReloadExcel,
  onRefreshAll,
  refreshing,
  onNavigateLogs,
  onToggleTheme,
  showPsWindow,
  onTogglePsWindow,
}: HeaderProps) {
  const { language, setLanguage, t } = useLanguage();

  return (
    <header className="card mb-6 p-4 md:p-6">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div className="flex items-center gap-4">
          <img src="/logo.png" alt="AP Manager Logo" className="h-14 w-14 object-contain" />
          <div>
            <h1 className="text-2xl font-bold text-cisco-navy dark:text-white">{t("appTitle")}</h1>
            <p className="text-sm text-slate-500 dark:text-slate-400">{t("appSubtitle")}</p>
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <div
            className="inline-flex overflow-hidden rounded-lg border border-slate-300 dark:border-slate-600"
            role="group"
            aria-label={t("language")}
          >
            <button
              type="button"
              className={`px-3 py-1.5 text-xs font-semibold transition ${
                language === "en"
                  ? "bg-cisco-blue text-white"
                  : "bg-white text-slate-600 hover:bg-slate-50 dark:bg-slate-800 dark:text-slate-200 dark:hover:bg-slate-700"
              }`}
              onClick={() => setLanguage("en")}
            >
              En
            </button>
            <button
              type="button"
              className={`px-3 py-1.5 text-xs font-semibold transition ${
                language === "ar"
                  ? "bg-cisco-blue text-white"
                  : "bg-white text-slate-600 hover:bg-slate-50 dark:bg-slate-800 dark:text-slate-200 dark:hover:bg-slate-700"
              }`}
              onClick={() => setLanguage("ar")}
            >
              Ar
            </button>
          </div>

          <span
            className={`inline-flex items-center gap-2 rounded-full px-3 py-1 text-xs font-medium ${
              backendOnline ? "bg-emerald-100 text-emerald-700" : "bg-red-100 text-red-700"
            }`}
          >
            <span className={`h-2 w-2 rounded-full ${backendOnline ? "bg-emerald-500" : "bg-red-500"}`} />
            {backendOnline ? t("backendOnline") : t("backendOffline")}
          </span>
          {lastUpdated && (
            <span className="text-xs text-slate-500">
              {t("updated")}: {new Date(lastUpdated).toLocaleString(language === "ar" ? "ar-EG" : "en-US")}
            </span>
          )}
          <button className="btn-secondary" onClick={onToggleTheme}>
            {t("theme")}
          </button>
          <button className="btn-secondary" onClick={onNavigateLogs}>
            {t("logs")}
          </button>
          <button className="btn-secondary" onClick={onReloadExcel}>
            {t("reloadExcel")}
          </button>
          <button className="btn-primary" onClick={onRefreshAll} disabled={refreshing}>
            {refreshing ? t("refreshing") : t("refreshAllClients")}
          </button>
        </div>
      </div>

      <label className="mt-4 flex items-center gap-2 text-sm text-slate-600 dark:text-slate-300">
        <input type="checkbox" checked={showPsWindow} onChange={(e) => onTogglePsWindow(e.target.checked)} />
        {t("showPsWindow")}
      </label>
    </header>
  );
}
