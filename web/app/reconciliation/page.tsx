/* eslint react/no-unescaped-entities: 0 */
"use client";

import { useEffect, useMemo, useState, useTransition } from "react";
import { format } from "date-fns";
import { createSupabaseBrowserClient } from "@/lib/supabaseClient";
import type { UnresolvedUnknown } from "@/lib/types";
import { ResolveDrawer } from "@/components/ResolveDrawer";
import { BulkResolveDrawer } from "@/components/BulkResolveDrawer";
import { Pagination } from "@/components/Pagination";
import { useToast } from "@/components/Toaster";
import clsx from "clsx";
import { getOrgId, sessionCacheGet, sessionCacheSet, unresolvedListKey } from "@/lib/cache";

type Cursor = { last_seen_at: string; id: string } | null;

const PAGE_SIZES = [25, 50] as const;

export default function ReconciliationPage() {
  const supabase = useMemo(createSupabaseBrowserClient, []);
  const { toast } = useToast();

  const [search, setSearch] = useState("");
  const [debouncedSearch, setDebouncedSearch] = useState("");
  const [pageSize, setPageSize] = useState<typeof PAGE_SIZES[number]>(25);
  const [cursor, setCursor] = useState<Cursor>(null);

  const [rows, setRows] = useState<UnresolvedUnknown[]>([]);
  const [isPending, startTransition] = useTransition();
  const [isLoading, setIsLoading] = useState(false);

  const [resolveRow, setResolveRow] = useState<UnresolvedUnknown | null>(null);
  const [bulkOpen, setBulkOpen] = useState(false);
  const [selected, setSelected] = useState<Record<string, boolean>>({});

  // Debounce search
  useEffect(() => {
    const t = setTimeout(() => setDebouncedSearch(search.trim()), 300);
    return () => clearTimeout(t);
  }, [search]);

  async function fetchPage(reset = false) {
    setIsLoading(true);
    try {
      const org = await getOrgId();
      const key = unresolvedListKey({
        org,
        q: debouncedSearch,
        pageSize,
        cursor: reset ? null : cursor
      });
      // Try cache first (30s)
      const cached = sessionCacheGet<UnresolvedUnknown[]>(key, 30_000);
      if (cached) {
        startTransition(() => {
          setRows(reset ? cached : [...rows, ...cached]);
          const tail = cached[cached.length - 1];
          setCursor(tail ? { last_seen_at: tail.last_seen_at, id: tail.id } : cursor);
        });
        return;
      }
      const query = supabase
        .from("unresolved_unknowns")
        .select("*")
        .order("last_seen_at", { ascending: false })
        .order("id", { ascending: false })
        .limit(pageSize);

      if (debouncedSearch) {
        // Support rfid_tag ilike, brand ilike, product_id exact (UUID-like)
        const maybeUuid =
          debouncedSearch.match(
            /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
          )?.[0] ?? null;
        const orFilters = [
          `rfid_tag.ilike.%${debouncedSearch}%`,
          `brand.ilike.%${debouncedSearch}%`
        ];
        if (maybeUuid) {
          orFilters.push(`product_id.eq.${maybeUuid}`);
        }
        query.or(orFilters.join(","));
      }

      if (!reset && cursor) {
        query.lte("last_seen_at", cursor.last_seen_at).lt("id", cursor.id);
      }

      const { data, error } = await query.returns<UnresolvedUnknown[]>();
      if (error) throw error;

      startTransition(() => {
        setRows(reset ? data : [...rows, ...data]);
        const tail = data[data.length - 1];
        setCursor(tail ? { last_seen_at: tail.last_seen_at, id: tail.id } : cursor);
      });
      sessionCacheSet(key, data);
    } catch (err: any) {
      toast({
        title: "Failed to load",
        description: err?.message ?? "Unknown error",
        variant: "error"
      });
    } finally {
      setIsLoading(false);
    }
  }

  // Initial + search/page size changes
  useEffect(() => {
    setCursor(null);
    setRows([]);
    // fetch fresh
    fetchPage(true);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [debouncedSearch, pageSize]);

  function handleResolvedSuccess(rfidTag: string) {
    setRows((prev) => prev.filter((r) => r.rfid_tag !== rfidTag));
    setSelected((prev) => {
      const copy = { ...prev };
      delete copy[rfidTag];
      return copy;
    });
    toast({
      title: "Resolved",
      description: "Unknown EPC resolved and bottle created",
      variant: "success"
    });
  }

  const selectedRows = useMemo(
    () => rows.filter((r) => selected[r.rfid_tag]),
    [rows, selected]
  );

  return (
    <div className="container">
      <div className="card">
        <div className="toolbar">
          <div className="toolbar-left">
            <h2>Reconciliation</h2>
          </div>
          <div className="toolbar-right">
            <label className="sr-only" htmlFor="search">
              Search
            </label>
            <input
              id="search"
              placeholder="Search rfid_tag, brand, or product_id"
              className="input"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
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
            <button
              className="btn"
              disabled={selectedRows.length === 0}
              onClick={() => setBulkOpen(true)}
              aria-disabled={selectedRows.length === 0}
            >
              Bulk Resolve ({selectedRows.length})
            </button>
          </div>
        </div>

        <div className="table-wrap">
          <table className="table">
            <thead>
              <tr>
                <th style={{ width: 36 }}>
                  <input
                    type="checkbox"
                    aria-label="Select all"
                    checked={rows.length > 0 && rows.every((r) => selected[r.rfid_tag])}
                    onChange={(e) => {
                      const checked = e.target.checked;
                      setSelected((prev) => {
                        const copy = { ...prev };
                        for (const r of rows) copy[r.rfid_tag] = checked;
                        return copy;
                      });
                    }}
                  />
                </th>
                <th>RFID Tag</th>
                <th>Last Seen</th>
                <th>Last Location</th>
                <th>Hints</th>
                <th className="num">Seen</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 && !isLoading ? (
                <tr>
                  <td colSpan={7} className="empty">
                    No unresolved unknowns found
                  </td>
                </tr>
              ) : (
                rows.map((row) => (
                  <tr key={row.id}>
                    <td>
                      <input
                        type="checkbox"
                        checked={!!selected[row.rfid_tag]}
                        onChange={(e) =>
                          setSelected((prev) => ({ ...prev, [row.rfid_tag]: e.target.checked }))
                        }
                        aria-label={`Select ${row.rfid_tag}`}
                      />
                    </td>
                    <td className="mono">{row.rfid_tag}</td>
                    <td>{format(new Date(row.last_seen_at), "PP p")}</td>
                    <td>{row.last_location ?? row.last_location_name ?? "—"}</td>
                    <td className="hints">
                      <span>{row.brand ?? "—"}</span>
                      <span>{row.type ?? "—"}</span>
                      <span>{row.size ?? "—"}</span>
                      <span>{row.price != null ? `$${row.price}` : "—"}</span>
                    </td>
                    <td className={clsx("num", "mono")}>{row.seen_count ?? 0}</td>
                    <td>
                      <button className="btn" onClick={() => setResolveRow(row)}>
                        Resolve
                      </button>
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

      <ResolveDrawer
        open={!!resolveRow}
        row={resolveRow}
        onClose={() => setResolveRow(null)}
        onResolved={handleResolvedSuccess}
      />
      <BulkResolveDrawer
        open={bulkOpen}
        rows={selectedRows}
        onClose={() => setBulkOpen(false)}
        onResolved={(rfidTags) => {
          setRows((prev) => prev.filter((r) => !rfidTags.includes(r.rfid_tag)));
          setSelected({});
        }}
      />
    </div>
  );
}


