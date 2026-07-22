import { useMemo, useState } from "react";
import type { AccessPoint } from "../api/client";
import { useLanguage } from "../context/LanguageContext";
import { getClientsEmoji } from "../utils/clientsEmoji";

type FilterStatus = "all" | "online" | "offline" | "error";
type SortKey = "name" | "ip" | "clients";

interface AccessPointTableProps {
  accessPoints: AccessPoint[];
  selectedRows: Set<number>;
  onSelectionChange: (rows: Set<number>) => void;
  rowLoading: Record<number, string | null>;
  rowStage: Record<number, string>;
  onGetClients: (row: number) => void;
  onApply: (row: number) => void;
  onOpenAp: (ip: string) => void;
  onBulkAction: (action: string) => void;
}

const PAGE_SIZE = 10;

function PasswordCell({ hasPassword }: { hasPassword: boolean }) {
  const { t } = useLanguage();
  const [visible, setVisible] = useState(false);
  if (!hasPassword) return <span className="text-slate-400">{t("empty")}</span>;
  return (
    <div className="flex items-center gap-2">
      <span>{visible ? t("passwordStored") : t("passwordHidden")}</span>
      <button
        className="text-xs text-cisco-blue hover:underline"
        onClick={() => setVisible((v) => !v)}
        title={visible ? t("hideHint") : t("showHint")}
      >
        {visible ? "🙈" : "👁"}
      </button>
    </div>
  );
}

export function AccessPointTable({
  accessPoints,
  selectedRows,
  onSelectionChange,
  rowLoading,
  rowStage,
  onGetClients,
  onApply,
  onOpenAp,
  onBulkAction,
}: AccessPointTableProps) {
  const { t } = useLanguage();
  const [search, setSearch] = useState("");
  const [filter, setFilter] = useState<FilterStatus>("all");
  const [sortKey, setSortKey] = useState<SortKey>("name");
  const [sortAsc, setSortAsc] = useState(true);
  const [page, setPage] = useState(1);

  const filtered = useMemo(() => {
    let rows = [...accessPoints];

    if (search.trim()) {
      const q = search.toLowerCase();
      rows = rows.filter(
        (ap) =>
          ap.accessPointName.toLowerCase().includes(q) ||
          ap.accessPointIP.includes(q) ||
          ap.macAddress.toLowerCase().includes(q) ||
          ap.currentSSID.toLowerCase().includes(q) ||
          ap.newWiFiSSID.toLowerCase().includes(q),
      );
    }

    if (filter !== "all") {
      rows = rows.filter((ap) => {
        const c = String(ap.clients).trim().toUpperCase();
        const status = ap.connectionStatus.toLowerCase();
        if (filter === "error") return c === "ERROR" || status.includes("error");
        if (filter === "online") return status.includes("online") || (c !== "" && c !== "ERROR" && c !== "...");
        if (filter === "offline") return status.includes("offline");
        return true;
      });
    }

    rows.sort((a, b) => {
      let cmp = 0;
      if (sortKey === "name") cmp = a.accessPointName.localeCompare(b.accessPointName);
      else if (sortKey === "ip") cmp = a.accessPointIP.localeCompare(b.accessPointIP);
      else {
        const na = Number(a.clients);
        const nb = Number(b.clients);
        cmp = (Number.isNaN(na) ? -1 : na) - (Number.isNaN(nb) ? -1 : nb);
      }
      return sortAsc ? cmp : -cmp;
    });

    return rows;
  }, [accessPoints, search, filter, sortKey, sortAsc]);

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const pageRows = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  const toggleAll = () => {
    if (selectedRows.size === pageRows.length) {
      onSelectionChange(new Set());
    } else {
      onSelectionChange(new Set(pageRows.map((r) => r.rowNumber)));
    }
  };

  const toggleRow = (row: number) => {
    const next = new Set(selectedRows);
    if (next.has(row)) next.delete(row);
    else next.add(row);
    onSelectionChange(next);
  };

  return (
    <div className="card p-4 md:p-6">
      <div className="mb-4 flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
        <div className="flex flex-wrap gap-2">
          <input
            className="input max-w-xs"
            placeholder={t("searchPlaceholder")}
            value={search}
            onChange={(e) => {
              setSearch(e.target.value);
              setPage(1);
            }}
          />
          <select
            className="input max-w-[160px]"
            value={filter}
            onChange={(e) => {
              setFilter(e.target.value as FilterStatus);
              setPage(1);
            }}
          >
            <option value="all">{t("filterAll")}</option>
            <option value="online">{t("filterOnline")}</option>
            <option value="offline">{t("filterOffline")}</option>
            <option value="error">{t("filterError")}</option>
          </select>
          <select
            className="input max-w-[160px]"
            value={sortKey}
            onChange={(e) => setSortKey(e.target.value as SortKey)}
          >
            <option value="name">{t("sortByName")}</option>
            <option value="ip">{t("sortByIp")}</option>
            <option value="clients">{t("sortByClients")}</option>
          </select>
          <button className="btn-secondary" onClick={() => setSortAsc((v) => !v)}>
            {sortAsc ? t("asc") : t("desc")}
          </button>
        </div>

        {selectedRows.size > 0 && (
          <div className="flex flex-wrap gap-2">
            <button className="btn-secondary" onClick={() => onBulkAction("get-clients")}>
              {t("bulkGetClients")} ({selectedRows.size})
            </button>
            <button className="btn-secondary" onClick={() => onBulkAction("apply-ssid")}>
              {t("bulkApplySsid")}
            </button>
            <button className="btn-secondary" onClick={() => onBulkAction("apply-password")}>
              {t("bulkApplyPassword")}
            </button>
            <button className="btn-secondary" onClick={() => onBulkAction("apply-all")}>
              {t("bulkApplyAll")}
            </button>
            <button className="btn-secondary" onClick={() => onBulkAction("export")}>
              {t("bulkExport")}
            </button>
            <button className="btn-secondary" onClick={() => onBulkAction("open-ap")}>
              {t("bulkOpenAp")}
            </button>
          </div>
        )}
      </div>

      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              <th>
                <input
                  type="checkbox"
                  checked={pageRows.length > 0 && pageRows.every((r) => selectedRows.has(r.rowNumber))}
                  onChange={toggleAll}
                />
              </th>
              <th>{t("colName")}</th>
              <th>{t("colIp")}</th>
              <th>{t("colMac")}</th>
              <th>{t("colUser")}</th>
              <th>{t("colPassword")}</th>
              <th>{t("colCurrentSsid")}</th>
              <th>{t("colNewSsid")}</th>
              <th>{t("colNewPassword")}</th>
              <th>{t("colClientsStatus")}</th>
              <th>{t("colClients")}</th>
              <th>{t("colConnectionStatus")}</th>
              <th>{t("colActions")}</th>
            </tr>
          </thead>
          <tbody>
            {pageRows.map((ap) => {
              const loading = Boolean(rowLoading[ap.rowNumber]);
              const stage = rowStage[ap.rowNumber];
              return (
                <tr key={ap.rowNumber}>
                  <td>
                    <input
                      type="checkbox"
                      checked={selectedRows.has(ap.rowNumber)}
                      onChange={() => toggleRow(ap.rowNumber)}
                    />
                  </td>
                  <td className="font-medium">{ap.accessPointName || t("empty")}</td>
                  <td>{ap.accessPointIP}</td>
                  <td className="whitespace-nowrap text-xs">{ap.macAddress || t("empty")}</td>
                  <td>{ap.accessUser || t("empty")}</td>
                  <td>
                    <PasswordCell hasPassword={ap.hasAccessPassword} />
                  </td>
                  <td>{ap.currentSSID || t("empty")}</td>
                  <td>{ap.newWiFiSSID || t("empty")}</td>
                  <td>
                    {ap.hasNewWiFiPassword ? (
                      <PasswordCell hasPassword={true} />
                    ) : (
                      t("empty")
                    )}
                  </td>
                  <td className="text-center text-lg">{getClientsEmoji(ap.clients)}</td>
                  <td>{String(ap.clients ?? "")}</td>
                  <td>{ap.connectionStatus || t("empty")}</td>
                  <td>
                    <div className="flex min-w-[220px] flex-col gap-1">
                      {loading && stage && (
                        <span className="flex items-center gap-1 text-xs text-cisco-blue">
                          <span className="spinner" /> {stage}
                        </span>
                      )}
                      <div className="flex flex-wrap gap-1">
                        <button
                          className="btn-secondary px-2 py-1 text-xs"
                          disabled={loading}
                          onClick={() => onGetClients(ap.rowNumber)}
                        >
                          {t("getClients")}
                        </button>
                        <button
                          className="btn-primary px-2 py-1 text-xs"
                          disabled={loading}
                          onClick={() => onApply(ap.rowNumber)}
                        >
                          {t("applyChanges")}
                        </button>
                        <button
                          className="btn-secondary px-2 py-1 text-xs"
                          onClick={() => onOpenAp(ap.accessPointIP)}
                        >
                          {t("openAp")}
                        </button>
                      </div>
                      {ap.lastUpdated && (
                        <span className="text-[10px] text-slate-400">{ap.lastUpdated}</span>
                      )}
                    </div>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <div className="mt-4 flex items-center justify-between text-sm">
        <span>
          {t("showing")} {(page - 1) * PAGE_SIZE + 1}–{Math.min(page * PAGE_SIZE, filtered.length)} {t("of")} {filtered.length}
        </span>
        <div className="flex gap-2">
          <button className="btn-secondary px-3 py-1" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>
            {t("previous")}
          </button>
          <span className="px-2 py-1">
            {t("page")} {page} / {totalPages}
          </span>
          <button
            className="btn-secondary px-3 py-1"
            disabled={page >= totalPages}
            onClick={() => setPage((p) => p + 1)}
          >
            {t("next")}
          </button>
        </div>
      </div>
    </div>
  );
}
