/* eslint react/no-unescaped-entities: 0 */
"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { createSupabaseBrowserClient } from "@/lib/supabaseClient";
import type { DashboardCards } from "@/lib/types";
import { dashboardKey, getOrgId, sessionCacheGet, sessionCacheSet } from "@/lib/cache";

export default function ReportingDashboardPage() {
  const supabase = useMemo(createSupabaseBrowserClient, []);
  const [cards, setCards] = useState<DashboardCards | null>(null);

  useEffect(() => {
    let mounted = true;
    (async () => {
      const org = await getOrgId();
      const key = dashboardKey(org);
      const cached = sessionCacheGet<DashboardCards>(key, 60_000);
      if (cached && mounted) {
        setCards(cached);
        return;
      }
      const { data, error } = await supabase
        .from("dashboard_cards")
        .select("*")
        .limit(1)
        .single();
      if (!mounted) return;
      if (!error) {
        const d = (data as any) as DashboardCards;
        setCards(d);
        sessionCacheSet(key, d);
      }
    })();
    return () => {
      mounted = false;
    };
  }, [supabase]);

  return (
    <div className="container">
      <div className="card" style={{ marginBottom: 16 }}>
        <h2>Reporting</h2>
        <div className="cards">
          <div className="card">
            <div className="muted">Active bottles</div>
            <div className="stat">{cards?.active_bottles ?? 0}</div>
          </div>
          <div className="card">
            <div className="muted">Unknown last 24h</div>
            <div className="stat">{cards?.unknown_last_24h ?? 0}</div>
          </div>
          <div className="card">
            <div className="muted">Today counts</div>
            <div className="stat">{cards?.todays_counts ?? 0}</div>
          </div>
        </div>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Pages</h3>
        <ul className="link-list">
          <li>
            <Link href="/reporting/counts">Daily Counts</Link>
          </li>
          <li>
            <Link href="/reporting/missing">Missing Today</Link>
          </li>
        </ul>
      </div>
    </div>
  );
}


