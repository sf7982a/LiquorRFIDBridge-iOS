import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createServiceClient, json } from '../_shared/supabase.ts'

/**
 * Create Session Edge Function
 * Inserts a new scan session into scan_sessions table
 * Called by iOS app when user starts a scanning session
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
    const {
      id,
      organization_id,
      session_type,
      status,
      device_name,
      location_id,
      started_by
    } = body

    if (!id || !organization_id || !session_type || !status || !device_name) {
      return json({
        error: 'Missing required fields: id, organization_id, session_type, status, device_name'
      }, 400)
    }

    // Validate session_type
    if (!['input', 'output', 'inventory'].includes(session_type)) {
      return json({
        error: 'Invalid session_type. Must be: input, output, or inventory'
      }, 400)
    }

    // Validate status
    if (!['active', 'stopped', 'completed'].includes(status)) {
      return json({
        error: 'Invalid status. Must be: active, stopped, or completed'
      }, 400)
    }

    // Insert session with server-side timestamp
    const { data, error } = await supabase
      .from('scan_sessions')
      .insert({
        id,
        organization_id,
        location_id: location_id || null,
        started_by: started_by || null,
        session_type,
        device_name,
        started_at: new Date().toISOString(),
        status,
        bottle_count: 0
      })
      .select()
      .single()

    if (error) {
      console.error('Database error:', error)
      return json({ error: error.message }, 500)
    }

    return json({
      success: true,
      session: data
    }, 201)

  } catch (error) {
    console.error('Error creating session:', error)
    return json({
      error: error instanceof Error ? error.message : 'Internal server error'
    }, 500)
  }
})
