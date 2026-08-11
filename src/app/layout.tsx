import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: "KDKMP Integrated Platform",
    template: "%s | KDKMP Integrated Platform",
  },
  description: "Integrated management platform for Koperasi Desa/Kelurahan Merah Putih.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="id">
      <body>{children}</body>
    </html>
  );
}
