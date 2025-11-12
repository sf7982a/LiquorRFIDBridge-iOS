/* eslint react/no-unescaped-entities: 0 */
"use client";

import { useEffect, useMemo, useState } from "react";
import { createSupabaseBrowserClient } from "@/lib/supabaseClient";
import type { MissingTodayRow } from "@/lib/types";

export default function MissingTodayPage() {
  const supabase = useMemo(createSupabaseBrowserClient, []);
  const [locationId, setLocationId] = useState("");
  const [rows, setRows] = useState<MissingTodayRow[]>([]);
  const [isLoading, setIsLoading] = useState(false);

  async function fetchRows() {
    setIsLoading(true);
    try {
      const query = (supabase as any).from("inventory_missing_today").select("*").order("brand", { ascending: true });
      if (locationId) query.eq("location_id", locationId);
      const { data, error } = await query;
      if (error) throw error;
      setRows(data);
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    fetchRows();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [locationId]);

  return (
    <div className="container">
      <div className="card">
        <div className="toolbar">
          <h2>Missing Today</h2>
          <div className="toolbar-right" style={{ gap: 6 }}>
            <input
              className="input"
              placeholder="Location UUID"
              value={locationId}
              onChange={(e) => setLocationId(e.target.value)}
            />
            <button className="btn secondary" onClick={fetchRows} disabled={isLoading}>
              {isLoading ? "Loading…" : "Refresh"}
            </button>
          </div>
        </div>
        <div className="table-wrap">
          <table className="table">
            <thead>
              <tr>
                <th>Brand</th>
                <th>Product</th>
                <th>Type</th>
                <th>Size (ml)</th>
                <th>Location</th>
                <th>RFID Tag</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 && !isLoading ? (
                <tr>
                  <td colSpan={6} className="empty">
                    No missing bottles
                  </td>
                </tr>
              ) : (
                rows.map((r) => (
                  <tr key={r.bottle_id}>
                    <td>{r.brand ?? "—"}</td>
                    <td>{r.product ?? "—"}</td>
                    <td>{r.type ?? "—"}</td>
                    <td className="num">{r.size_ml ?? "—"}</td>
                    <td>{r.location_name ?? r.location_id ?? "—"}</td>
                    <td className="mono">{r.rfid_tag}</td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}


