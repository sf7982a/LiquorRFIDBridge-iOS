import type { Metadata } from "next";
import "./globals.css";
import { Toaster } from "@/components/Toaster";
import { AuthGate } from "@/components/AuthGate";
import { HeaderAuth } from "@/components/HeaderAuth";
import { Analytics } from "@vercel/analytics/react";
import { SpeedInsights } from "@vercel/speed-insights/next";

export const metadata: Metadata = {
  title: "LiquorRFID Admin",
  description: "Reconciliation, Bottles Admin, and Reporting"
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <Toaster>
          <div className="app-shell">
            <header className="app-header">
              <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
                <h1 className="app-title">LiquorRFID Admin</h1>
                <HeaderAuth />
              </div>
            </header>
            <main className="app-main">
              <AuthGate>{children}</AuthGate>
            </main>
          </div>
        </Toaster>
        <Analytics />
        <SpeedInsights />
      </body>
    </html>
  );
}


