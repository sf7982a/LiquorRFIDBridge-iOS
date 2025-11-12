/* eslint react/no-unescaped-entities: 0 */
"use client";

import { useEffect, useMemo, useState, useTransition } from "react";
import { format } from "date-fns";
import clsx from "clsx";
import { createSupabaseBrowserClient } from "@/lib/supabaseClient";
import type { BottleListItem } from "@/lib/types";
import { Pagination } from "@/components/Pagination";
import { bottlesListKey, getOrgId, sessionCacheGet, sessionCacheSet } from "@/lib/cache";

type Cursor = { last_scanned: string | null; id: string } | null;
const PAGE_SIZES = [25, 50] as const;
const STATUSES = ["active", "inactive", "unknown"] as const;

export default function BottlesPage() {
  const supabase = useMemo(createSupabaseBrowserClient, []);
  const [pageSize, setPageSize] = useState<typeof PAGE_SIZES[number]>(25);
  const [cursor, setCursor] = useState<Cursor>(null);
  const [rows, setRows] = useState<BottleListItem[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [isPending, startTransition] = useTransition();

  // filters
  const [status, setStatus] = useState<string>(""); // any
  const [locationId, setLocationId] = useState("");
  const [brand, setBrand] = useState("");
  const [type, setType] = useState("");

  async function fetchPage(reset = false) {
    setIsLoading(true);
    try {
      const org = await getOrgId();
      const key = bottlesListKey({
        org,
        filters: { status, location_id: locationId, brand, type },
        sort: "last_scanned_desc",
        pageSize,
        cursor: reset ? null : cursor
      });
      const cached = sessionCacheGet<BottleListItem[]>(key, 30_000);
      if (cached) {
        startTransition(() => {
          setRows(reset ? cached : [...rows, ...cached]);
          const tail = cached[cached.length - 1];
          setCursor(tail ? { last_scanned: tail.last_scanned ?? null, id: tail.id } : cursor);
        });
        return;
      }
      const query = supabase
        .from("bottles")
        .select(
          "id, rfid_tag, brand, product, type, size_ml, location_id, location_name, status, last_scanned"
        )
        .order("last_scanned", { ascending: false, nullsFirst: false })
        .order("id", { ascending: false })
        .limit(pageSize);

      if (status) query.eq("status", status);
      if (locationId) query.eq("location_id", locationId);
      if (brand) query.ilike("brand", `%${brand}%`);
      if (type) query.ilike("type", `%${type}%`);
      if (!reset && cursor) {
        if (cursor.last_scanned) query.lte("last_scanned", cursor.last_scanned);
        query.lt("id", cursor.id);
      }

      const { data, error } = await query.returns<BottleListItem[]>();
      if (error) throw error;

      startTransition(() => {
        setRows(reset ? data : [...rows, ...data]);
        const tail = data[data.length - 1];
        setCursor(
          tail ? { last_scanned: tail.last_scanned ?? null, id: tail.id } : cursor
        );
      });
      sessionCacheSet(key, data);
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    setCursor(null);
    setRows([]);
    fetchPage(true);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [status, locationId, brand, type, pageSize]);

  return (
    <div className="container">
      <div className="card">
        <div className="toolbar">
          <div className="toolbar-left">
            <h2>Admin Bottles</h2>
          </div>
          <div className="toolbar-right" style={{ gap: 6 }}>
            <select
              className="select"
              value={status}
              onChange={(e) => setStatus(e.target.value)}
              aria-label="Status"
            >
              <option value="">Status: Any</option>
              {STATUSES.map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </select>
            <input
              className="input"
              placeholder="Location UUID"
              value={locationId}
              onChange={(e) => setLocationId(e.target.value)}
              aria-label="Location"
            />
            <input
              className="input"
              placeholder="Brand"
              value={brand}
              onChange={(e) => setBrand(e.target.value)}
              aria-label="Brand"
            />
            <input
              className="input"
              placeholder="Type"
              value={type}
              onChange={(e) => setType(e.target.value)}
              aria-label="Type"
            />
            <select
              className="select"
              value={pageSize}
              onChange={(e) => setPageSize(Number(e.target.value) as any)}
            >
              {PAGE_SIZES.map((n) => (
                <option key={n} value={n}>
                  {n}/page
                </option>
              ))}
            </select>
          </div>
        </div>
        <div className="table-wrap">
          <table className="table">
            <thead>
              <tr>
                <th>Brand</th>
                <th>Product</th>
                <th>Type</th>
                <th className="num">Size (ml)</th>
                <th>Location</th>
                <th>Status</th>
                <th>RFID</th>
                <th>Last Scanned</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 && !isLoading ? (
                <tr>
                  <td colSpan={8} className="empty">
                    No bottles
                  </td>
                </tr>
              ) : (
                rows.map((r) => (
                  <tr key={r.id}>
                    <td>
                      <a href={`/bottles/${r.id}`}>{r.brand ?? "—"}</a>
                    </td>
                    <td>{r.product ?? "—"}</td>
                    <td>{r.type ?? "—"}</td>
                    <td className={clsx("num", "mono")}>
                      {r.size_ml != null ? r.size_ml : "—"}
                    </td>
                    <td>{r.location_name ?? r.location_id ?? "—"}</td>
                    <td>{r.status ?? "—"}</td>
                    <td className="mono">{r.rfid_tag}</td>
                    <td>
                      {r.last_scanned ? format(new Date(r.last_scanned), "PP p") : "—"}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
        <Pagination
          isLoading={isLoading || isPending}
          onNext={() => fetchPage(false)}
          canNext={rows.length > 0}
        />
      </div>
    </div>
  );
}


