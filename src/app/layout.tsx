import type { Metadata } from "next";
import "./globals.css";
export const metadata: Metadata = { title: "BNB Manager | Quản lý căn hộ", description: "Quản lý căn hộ cho thuê ngắn ngày" };
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) { return <html lang="vi"><body>{children}</body></html>; }
