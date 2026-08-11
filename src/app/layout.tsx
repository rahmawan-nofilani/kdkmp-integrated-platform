import type { Metadata } from "next";
import "./globals.css";
import "./manager-command-center.css";
import "./design-system-v1.css";
import "./pos-workspace.css";
import "./pos-shift-control.css";
import "./pos-catalog.css";
import "./pos-cart.css";
import "./pos-payment.css";

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
