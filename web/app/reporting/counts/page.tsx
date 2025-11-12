/* eslint react/no-unescaped-entities: 0 */
"use client";

import { useEffect, useMemo, useState } from "react";
import { format } from "date-fns";
import { createSupabaseBrowserClient } from "@/lib/supabaseClient";
import type { CountsDailyRow } from "@/lib/types";
import { Pagination } from "@/components/Pagination";
import { downloadCsv } from "@/lib/csv";
import { RoleGuard } from "@/components/RoleGuard";
import { countsDailyKey, getOrgId, sessionCacheGet, sessionCacheSet } from "@/lib/cache";

type Cursor = { counted_date: string; id: string } | null;
const PAGE_SIZES = [25, 50] as const;

export default function DailyCountsPage() {
  const supabase = useMemo(createSupabaseBrowserClient, []);
  const [rows, setRows] = useState<CountsDailyRow[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [pageSize, setPageSize] = useState<typeof PAGE_SIZES[number]>(25);
  const [cursor, setCursor] = useState<Cursor>(null);

  // filters
  const [startDate, setStartDate] = useState(() =>
    format(new Date(Date.now() - 6 * 24 * 60 * 60 * 1000), "yyyy-MM-dd")
  );
  const [endDate, setEndDate] = useState(() => format(new Date(), "yyyy-MM-dd"));
  const [locationId, setLocationId] = useState("");
  const [brand, setBrand] = useState("");
  const [product, setProduct] = useState("");
  const [type, setType] = useState("");
  const [size, setSize] = useState("");

  function applyFilters(query: any) {
    if (startDate) query.gte("counted_date", startDate);
    if (endDate) query.lte("counted_date", endDate);
    if (locationId) query.eq("location_id", locationId);
    if (brand) query.ilike("brand", `%${brand}%`);
    if (product) query.ilike("product", `%${product}%`);
    if (type) query.ilike("type", `%${type}%`);
    if (size) query.ilike("size", `%${size}%`);
  }

  async function fetchPage(reset = false) {
    setIsLoading(true);
    try {
      const org = await getOrgId();
      const key = countsDailyKey({
        org,
        startDate,
        endDate,
        location_id: locationId || undefined,
        facets: { brand, product, type, size },
        pageSize,
        cursor: reset ? null : cursor
      });
      const cached = sessionCacheGet<CountsDailyRow[]>(key, 60_000);
      if (cached) {
        setRows(reset ? cached : [...rows, ...cached]);
        const tail = cached[cached.length - 1];
        setCursor(tail ? { counted_date: tail.counted_date, id: tail.id } : cursor);
        return;
      }
      const query = supabase
        .from("inventory_counts_daily")
        .select("*")
        .order("counted_date", { ascending: false })
        .order("id", { ascending: false })
        .limit(pageSize);

      applyFilters(query);
      if (!reset && cursor) {
        query.lte("counted_date", cursor.counted_date).lt("id", cursor.id);
      }

      const { data, error } = await query.returns<CountsDailyRow[]>();
      if (error) throw error;
      setRows(reset ? data : [...rows, ...data]);
      const tail = data[data.length - 1];
      setCursor(tail ? { counted_date: tail.counted_date, id: tail.id } : cursor);
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
  }, [startDate, endDate, locationId, brand, product, type, size, pageSize]);

  async function onExportCsv() {
    await downloadCsv("inventory_counts_daily_export", "counts_daily.csv", {
      select: "*",
      counted_date: startDate && endDate ? `gte.${startDate}&counted_date=lte.${endDate}` : "",
      location_id: locationId ? `eq.${locationId}` : "",
      brand: brand ? `ilike.*${encodeURIComponent(brand)}*` : "",
      product: product ? `ilike.*${encodeURIComponent(product)}*` : "",
      type: type ? `ilike.*${encodeURIComponent(type)}*` : "",
      size: size ? `ilike.*${encodeURIComponent(size)}*` : ""
    });
  }

  return (
    <div className="container">
      <div className="card">
        <div className="toolbar">
          <h2>Daily Counts</h2>
          <div className="toolbar-right" style={{ gap: 6 }}>
            <input
              className="input"
              type="date"
              value={startDate}
              onChange={(e) => setStartDate(e.target.value)}
            />
            <input className="input" type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)} />
            <input
              className="input"
              placeholder="Location UUID"
              value={locationId}
              onChange={(e) => setLocationId(e.target.value)}
            />
            <input className="input" placeholder="Brand" value={brand} onChange={(e) => setBrand(e.target.value)} />
            <input
              className="input"
              placeholder="Product"
              value={product}
              onChange={(e) => setProduct(e.target.value)}
            />
            <input className="input" placeholder="Type" value={type} onChange={(e) => setType(e.target.value)} />
            <input className="input" placeholder="Size" value={size} onChange={(e) => setSize(e.target.value)} />
            <select className="select" value={pageSize} onChange={(e) => setPageSize(Number(e.target.value) as any)}>
              {PAGE_SIZES.map((n) => (
                <option key={n} value={n}>
                  {n}/page
                </option>
              ))}
            </select>
            <RoleGuard allow={["admin", "manager"]}>
              <button className="btn secondary" onClick={onExportCsv}>
              Export CSV
              </button>
            </RoleGuard>
          </div>
        </div>

        <div className="table-wrap">
          <table className="table">
            <thead>
              <tr>
                <th>Date</th>
                <th>Location</th>
                <th>Brand</th>
                <th>Product</th>
                <th>Type</th>
                <th>Size</th>
                <th className="num">Total</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 && !isLoading ? (
                <tr>
                  <td colSpan={7} className="empty">
                    No results
                  </td>
                </tr>
              ) : (
                rows.map((r) => (
                  <tr key={r.id}>
                    <td>{r.counted_date}</td>
                    <td>{r.location_name ?? r.location_id ?? "—"}</td>
                    <td>{r.brand ?? "—"}</td>
                    <td>{r.product ?? "—"}</td>
                    <td>{r.type ?? "—"}</td>
                    <td>{r.size ?? "—"}</td>
                    <td className="num">{r.total ?? 0}</td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
        <Pagination isLoading={isLoading} onNext={() => fetchPage(false)} canNext={rows.length > 0} />
      </div>
    </div>
  );
}


