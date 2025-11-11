import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createServiceClient, json } from '../_shared/supabase.ts'

/**
 * upsert_bottle_on_scan
 * Idempotently upserts bottles by EPC (rfid_tag) and optionally writes daily inventory_counts.
 *
 * Body:
 * {
 *   organization_id: string (uuid),
 *   session_id?: string (uuid),
 *   session_type?: 'inventory' | 'input' | 'output',
 *   location_id: string (uuid),
 *   tags: Array<{ rfid_tag: string, rssi?: number, timestamp?: string }>
 * }
 */
Deno.serve(async (req) => {
  // CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
        'Access-Control-Allow-Methods': 'POST, OPTIONS'
      }
    })
  }

  try {
    if (req.method !== 'POST') {
      return json({ error: 'Only POST is supported' }, 405)
    }
    const supabase = createServiceClient()
    const body = await req.json()

    const {
      organization_id,
      session_id,
      session_type,
      location_id,
      tags
    } = body || {}

    if (!organization_id || !location_id || !Array.isArray(tags)) {
      return json({ error: 'Missing required fields: organization_id, location_id, tags (array)' }, 400)
    }
    if (tags.length === 0) {
      return json({ error: 'tags array cannot be empty' }, 400)
    }
    if (tags.length > 100) {
      return json({ error: 'Maximum 100 tags per batch' }, 400)
    }

    // Deduplicate by rfid_tag within request
    const seen = new Set<string>()
    const deduped = []
    for (const t of tags) {
      if (!t?.rfid_tag || typeof t.rfid_tag !== 'string') continue
      if (seen.has(t.rfid_tag)) continue
      seen.add(t.rfid_tag)
      deduped.push(t)
    }
    if (deduped.length === 0) {
      return json({ error: 'No valid tags found' }, 400)
    }

    // If session_type not provided but session_id is, resolve from DB
    let resolvedSessionType = session_type
    if (!resolvedSessionType && session_id) {
      const { data: sess, error: sessErr } = await supabase
        .from('scan_sessions')
        .select('session_type')
        .eq('id', session_id)
        .single()
      if (!sessErr && sess?.session_type) {
        resolvedSessionType = sess.session_type
      }
    }

    // Resolve existing bottles first (update-only to avoid NOT NULL violations on your schema)
    const epcs = deduped.map((t: any) => t.rfid_tag)
    const { data: existing, error: existErr } = await supabase
      .from('bottles')
      .select('id, rfid_tag')
      .eq('organization_id', organization_id)
      .in('rfid_tag', epcs)
    if (existErr) {
      console.error('bottles lookup error:', existErr)
      return json({ error: existErr.message }, 500)
    }
    const tagToBottleId = new Map<string, string>()
    for (const row of (existing || [])) tagToBottleId.set(row.rfid_tag, row.id)

    // Update only existing bottles (status/location/last_scanned)
    let updatedCount = 0
    for (const t of deduped) {
      const bottleId = tagToBottleId.get(t.rfid_tag)
      if (!bottleId) continue
      const updateRow: any = {
        location_id: location_id,
        status: 'active',
        last_scanned: t.timestamp || new Date().toISOString()
      }
      const { error: updErr } = await supabase
        .from('bottles')
        .update(updateRow)
        .eq('id', bottleId)
        .eq('organization_id', organization_id)
      if (!updErr) updatedCount++
    }

    // Unknown EPCs in a single upsert (no seen_count override on conflict)
    const nowIso = new Date().toISOString()
    const unknownRows = deduped
      .filter((t: any) => !tagToBottleId.get(t.rfid_tag))
      .map((t: any) => ({
        organization_id,
        rfid_tag: t.rfid_tag,
        location_id,
        last_seen_at: t.timestamp || nowIso
      }))
    if (unknownRows.length > 0) {
      const { error: upsertUnknownErr } = await supabase
        .from('unknown_epcs')
        .upsert(unknownRows, { onConflict: 'organization_id,rfid_tag' })
        .select('id') // optional
      if (upsertUnknownErr) {
        console.error('unknown_epcs upsert error:', upsertUnknownErr)
      }
    }

    // If inventory session, write daily counts (idempotent via unique constraint)
    let countsInserted = 0
    if (resolvedSessionType === 'inventory') {
      const countsRows: any[] = []
      for (const t of deduped) {
        const bottle_id = tagToBottleId.get(t.rfid_tag)
        if (!bottle_id) continue
        const ts = t.timestamp ? new Date(t.timestamp) : new Date()
        // counted_at as UTC date string (YYYY-MM-DD)
        const counted_at = ts.toISOString().slice(0, 10)
        countsRows.push({
          organization_id,
          bottle_id,
          location_id,
          counted_at,
          session_id: session_id || null,
          rssi: typeof t.rssi === 'number' ? t.rssi : null,
          metadata: {}
        })
      }
      if (countsRows.length > 0) {
        const { data: countsData, error: countsErr } = await supabase
          .from('inventory_counts')
          .upsert(countsRows, {
            onConflict: 'organization_id,bottle_id,counted_at,location_id'
          })
          .select('id')
        if (countsErr) {
          console.error('inventory_counts upsert error:', countsErr)
          return json({ error: countsErr.message }, 500)
        }
        countsInserted = countsData?.length || 0
      }
    }

    const skippedList = deduped
      .filter((t: any) => !tagToBottleId.get(t.rfid_tag))
      .map((t: any) => t.rfid_tag)

    return json({
      success: true,
      updated_bottles: updatedCount,
      counts_inserted: countsInserted,
      skipped_new_epcs: skippedList,
      skipped_new_epcs_count: skippedList.length
    }, 200)
  } catch (err) {
    console.error('upsert_bottle_on_scan error:', err)
    return json({ error: err instanceof Error ? err.message : 'Internal server error' }, 500)
  }
})


