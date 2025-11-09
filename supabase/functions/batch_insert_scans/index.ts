import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createServiceClient, json } from '../_shared/supabase.ts'

/**
 * Batch Insert Scans Edge Function
 * Inserts RFID tag reads into rfid_scans table in batches
 * Called by iOS app when tags are read or offline queue is flushed
 */
Deno.serve(async (req) => {
  // Handle CORS preflight
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
    const supabase = createServiceClient()
    const body = await req.json()

    // Validate required fields
    const { organization_id, session_id, scans } = body

    if (!organization_id || !scans || !Array.isArray(scans)) {
      return json({
        error: 'Missing required fields: organization_id, scans (array)'
      }, 400)
    }

    if (scans.length === 0) {
      return json({
        error: 'scans array cannot be empty'
      }, 400)
    }

    if (scans.length > 100) {
      return json({
        error: 'Maximum 100 scans per batch'
      }, 400)
    }

    // Validate each scan has required fields
    for (let i = 0; i < scans.length; i++) {
      const scan = scans[i]
      if (!scan.id || !scan.rfid_tag || scan.rssi === undefined) {
        return json({
          error: `Scan at index ${i} missing required fields: id, rfid_tag, rssi`
        }, 400)
      }
    }

    // Build scan records with organization_id and session_id
    const scanRecords = scans.map(scan => ({
      id: scan.id,
      organization_id,
      session_id: session_id || null,
      location_id: scan.location_id || null,
      rfid_tag: scan.rfid_tag,
      rssi: scan.rssi,
      timestamp: scan.timestamp || new Date().toISOString(),
      processed: scan.processed || false,
      metadata: scan.metadata || {}
    }))

    // Insert all scans in single batch
    const { data, error } = await supabase
      .from('rfid_scans')
      .insert(scanRecords)
      .select()

    if (error) {
      console.error('Database error:', error)
      return json({ error: error.message }, 500)
    }

    return json({
      success: true,
      inserted: data.length,
      scans: data
    }, 201)

  } catch (error) {
    console.error('Error inserting scans:', error)
    return json({
      error: error instanceof Error ? error.message : 'Internal server error'
    }, 500)
  }
})
