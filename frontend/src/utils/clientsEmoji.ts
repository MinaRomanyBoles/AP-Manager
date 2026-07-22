export function getClientsEmoji(value: string | number | null | undefined): string {
  if (value === null || value === undefined || value === "") return "🔃";
  const str = String(value).trim();
  if (str === "") return "🔃";
  if (str.toUpperCase() === "ERROR") return "⚠️";
  if (str === "...") return "🏃‍♂️‍➡️";
  if (str === "0" || str === "0.0") return "0️⃣";
  const num = Number(str);
  if (!Number.isNaN(num) && num >= 0) {
    if (num === 0) return "0️⃣";
    if (num > 20) return `💻 × ${num}`;
    return "💻".repeat(num);
  }
  return "🔃";
}

export function getConnectionBadge(status: string, clients: string | number): "online" | "offline" | "error" | "loading" | "unknown" {
  const c = String(clients).trim();
  if (c === "...") return "loading";
  if (c.toUpperCase() === "ERROR") return "error";
  if (/online/i.test(status)) return "online";
  if (/offline|error/i.test(status)) return status.toLowerCase().includes("error") ? "error" : "offline";
  if (c !== "" && c !== "🔃") return "online";
  return "unknown";
}
