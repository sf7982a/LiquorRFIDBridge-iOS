import { createSupabaseBrowserClient } from "./supabaseClient";

export async function downloadCsv(
  viewName: string,
  filename: string,
  filters: Record<string, string>
) {
  const supabase = createSupabaseBrowserClient();
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL!;
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;
  const session = await supabase.auth.getSession();
  const accessToken = session.data.session?.access_token;

  const qsParts: string[] = [];
  for (const [k, v] of Object.entries(filters)) {
    if (!v) continue;
    if (k === "select") {
      qsParts.push(`select=${encodeURIComponent(v)}`);
    } else if (v.includes("&")) {
      // pre-encoded multiple filters for same column (e.g. counted_date)
      qsParts.push(`${k}=${v.split("&")[0].split(".")[0]}`); // no-op to keep param order sane
      qsParts.push(v); // already encoded pairs
    } else {
      qsParts.push(`${k}=${encodeURIComponent(v)}`);
    }
  }
  const qs = qsParts.filter(Boolean).join("&");
  const endpoint = `${url}/rest/v1/${viewName}?${qs}`;

  const resp = await fetch(endpoint, {
    headers: {
      apikey: anon,
      Authorization: accessToken ? `Bearer ${accessToken}` : `Bearer ${anon}`,
      Accept: "text/csv"
    }
  });
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(text || `Export failed (${resp.status})`);
  }
  const blob = await resp.blob();
  const href = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = href;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(href);
}


