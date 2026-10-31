export const money = (value: number | string | null | undefined) =>
  new Intl.NumberFormat("vi-VN", { style: "currency", currency: "VND", maximumFractionDigits: 0 }).format(Number(value || 0));
export const date = (value: string | null | undefined) => value
  ? new Intl.DateTimeFormat("vi-VN", { day: "2-digit", month: "2-digit", year: "numeric", timeZone: "Asia/Ho_Chi_Minh" }).format(new Date(`${value.slice(0, 10)}T12:00:00+07:00`)) : "—";
