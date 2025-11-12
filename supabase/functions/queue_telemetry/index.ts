import { createServiceClient, json } from "../_shared/supabase.ts";

type TelemetryPayload = {
  organization_id: string;
  device_name?: string;
  app_version?: string;
  queue_depth: number;
  last_flush_succeeded: number;
  last_flush_failed: number;
  permanent_failure_count: number;
  timestamp?: string; // ISO string
};

function decodeJwtSub(authHeader: string | null): string | null {
  if (!authHeader) return null;
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  const parts = token.split(".");
  if (parts.length < 2) return null;
  try {
    const payload = JSON.parse(atob(parts[1]));
    return typeof payload.sub === "string" ? payload.sub : null;
  } catch {
    return null;
  }
}

async function handler(req: Request): Promise<Response> {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  const authHeader = req.headers.get("Authorization");
  // verify_jwt=true will gate auth; we still decode user id for audit metadata
  const userId = decodeJwtSub(authHeader);

  let body: TelemetryPayload | null = null;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  if (
    !body ||
    !body.organization_id ||
    typeof body.queue_depth !== "number" ||
    typeof body.last_flush_succeeded !== "number" ||
    typeof body.last_flush_failed !== "number" ||
    typeof body.permanent_failure_count !== "number"
  ) {
    return json({ error: "invalid_payload" }, 400);
  }

  // Write as activity_log for visibility
  try {
    const supabase = createServiceClient();
    const { error } = await supabase.from("activity_logs").insert({
      organization_id: body.organization_id,
      actor_id: userId,
      action: "queue_telemetry",
      subject_type: "device",
      subject_id: null,
      metadata: {
        device_name: body.device_name ?? null,
        app_version: body.app_version ?? null,
        queue_depth: body.queue_depth,
        last_flush_succeeded: body.last_flush_succeeded,
        last_flush_failed: body.last_flush_failed,
        permanent_failure_count: body.permanent_failure_count,
        timestamp: body.timestamp ?? new Date().toISOString()
      }
    });
    if (error) {
      return json({ error: "insert_failed", details: error.message }, 500);
    }
    return json({ ok: true });
  } catch (err: any) {
    return json({ error: "server_error", details: err?.message ?? String(err) }, 500);
  }
}

export default handler;

// Edge runtime entrypoint
Deno.serve(handler);


