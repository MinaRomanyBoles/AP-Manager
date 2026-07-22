import type { AccessPoint } from "../api/client";
import { useLanguage } from "../context/LanguageContext";
import { getConnectionBadge } from "../utils/clientsEmoji";

interface SummaryCardsProps {
  accessPoints: AccessPoint[];
  lastExcelSync: string | null;
}

export function SummaryCards({ accessPoints, lastExcelSync }: SummaryCardsProps) {
  const { t } = useLanguage();

  const total = accessPoints.length;
  let online = 0;
  let offline = 0;
  let errors = 0;
  let totalClients = 0;

  for (const ap of accessPoints) {
    const badge = getConnectionBadge(ap.connectionStatus, ap.clients);
    if (badge === "online") online++;
    else if (badge === "error") errors++;
    else if (badge === "offline") offline++;

    const c = String(ap.clients).trim();
    if (c && c !== "..." && c.toUpperCase() !== "ERROR") {
      const n = Number(c);
      if (!Number.isNaN(n)) totalClients += n;
    }
  }

  const cards = [
    { label: t("totalAccessPoints"), value: total },
    { label: t("onlineAps"), value: online, color: "text-emerald-600" },
    { label: t("offlineAps"), value: offline, color: "text-slate-500" },
    { label: t("totalConnectedClients"), value: totalClients, color: "text-cisco-blue" },
    { label: t("apsWithErrors"), value: errors, color: "text-red-600" },
    { label: t("lastExcelSync"), value: lastExcelSync ?? t("empty"), small: true },
  ];

  return (
    <div className="grid grid-cols-2 gap-4 md:grid-cols-3 xl:grid-cols-6">
      {cards.map((card) => (
        <div key={card.label} className="card p-4">
          <p className="text-xs font-medium uppercase tracking-wide text-slate-500">{card.label}</p>
          <p className={`mt-1 ${card.small ? "text-sm" : "text-2xl font-bold"} ${card.color ?? ""}`}>
            {card.value}
          </p>
        </div>
      ))}
    </div>
  );
}
