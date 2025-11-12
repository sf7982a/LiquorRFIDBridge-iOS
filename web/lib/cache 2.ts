import { createSupabaseBrowserClient } from "./supabaseClient";

type CacheRecord<T> = {
  t: number; // stored at (ms)
  v: T; // value
};

export async function getOrgId(): Promise<string> {
  try {
    const supabase = createSupabaseBrowserClient();
    const { data } = await supabase.auth.getUser();
    const org =
      ((data.user?.user_metadata as any)?.organization_id as string | undefined) ??
      ((data.user?.user_metadata as any)?.org as string | undefined) ??
      "unknown";
    return org;
  } catch {
    return "unknown";
  }
}

export function sessionCacheGet<T>(key: string, maxAgeMs: number): T | null {
  try {
    const raw = sessionStorage.getItem(key);
    if (!raw) return null;
    const rec = JSON.parse(raw) as CacheRecord<T>;
    if (!rec || typeof rec.t !== "number") return null;
    if (Date.now() - rec.t > maxAgeMs) return null;
    return rec.v;
  } catch {
    return null;
  }
}

export function sessionCacheSet<T>(key: string, value: T): void {
  try {
    const rec: CacheRecord<T> = { t: Date.now(), v: value };
    sessionStorage.setItem(key, JSON.stringify(rec));
  } catch {
    // ignore
  }
}

// Helpers to build cache keys

export function unresolvedListKey(params: {
  org: string;
  q: string;
  pageSize: number;
  cursor: { last_seen_at: string; id: string } | null;
}) {
  const cursorStr = params.cursor ? `${params.cursor.last_seen_at}|${params.cursor.id}` : "start";
  return `unresolved:list:${params.org}:${params.q || "-" }:${params.pageSize}:${cursorStr}`;
}

export function bottlesListKey(params: {
  org: string;
  filters: { status?: string; location_id?: string; brand?: string; type?: string };
  sort: "last_scanned_desc";
  pageSize: number;
  cursor: { last_scanned: string | null; id: string } | null;
}) {
  const f = params.filters;
  const filtersStr = `s=${f.status || ""},l=${f.location_id || ""},b=${f.brand || ""},t=${
    f.type || ""
  }`;
  const cursorStr = params.cursor
    ? `${params.cursor.last_scanned || "null"}|${params.cursor.id}`
    : "start";
  return `bottles:list:${params.org}:${filtersStr}:${params.sort}:${params.pageSize}:${cursorStr}`;
}

function hashString(input: string): string {
  let h = 5381;
  for (let i = 0; i < input.length; i++) {
    h = (h * 33) ^ input.charCodeAt(i);
  }
  return (h >>> 0).toString(16);
}

export function countsDailyKey(params: {
  org: string;
  startDate: string;
  endDate: string;
  location_id?: string;
  facets: { brand?: string; product?: string; type?: string; size?: string };
  pageSize: number;
  cursor: { counted_date: string; id: string } | null;
}) {
  const range = `${params.startDate}_${params.endDate}`;
  const loc = params.location_id || "-";
  const facetHash = hashString(
    JSON.stringify({
      b: params.facets.brand || "",
      p: params.facets.product || "",
      t: params.facets.type || "",
      s: params.facets.size || ""
    })
  );
  const cursorStr = params.cursor
    ? `${params.cursor.counted_date}|${params.cursor.id}`
    : "start";
  return `countsDaily:${params.org}:${range}:${loc}:${facetHash}:${params.pageSize}:${cursorStr}`;
}

export function dashboardKey(org: string) {
  return `dashboard:${org}:v1`;
}


