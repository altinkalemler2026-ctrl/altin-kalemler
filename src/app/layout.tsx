import type { Metadata } from "next";
import type { ReactNode } from "react";
import { Geist } from "next/font/google";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Altın Kalemler",
  description:
    "1-12. sınıf öğrencileri için eğitim ve bilgi yarışması platformu",
};

// Açık React tipi: temiz CI ortamında .next/types altındaki global
// üretilmiş Next türlerine (LayoutProps) bağımlılık YOK.
export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html
      lang="tr"
      className={`${geistSans.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col">{children}</body>
    </html>
  );
}
