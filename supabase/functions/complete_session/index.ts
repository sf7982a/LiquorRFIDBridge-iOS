import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createServiceClient, json } from '../_shared/supabase.ts'

/**
 * Complete Session Edge Function
 * Updates a scan session status and final stats
 * Called by iOS app when user stops/completes a scanning session
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
    const { id, status, ended_at, bottle_count } = body

    if (!id || !status) {
      return json({
        error: 'Missing required fields: id, status'
      }, 400)
    }

    // Validate status
    if (!['stopped', 'completed'].includes(status)) {
      return json({
        error: 'Invalid status. Must be: stopped or completed'
      }, 400)
    }

    // Build update object
    const updateData: any = {
      status,
      ended_at: ended_at || new Date().toISOString()
    }

    // Only update bottle_count if provided
    if (bottle_count !== undefined && bottle_count !== null) {
      updateData.bottle_count = bottle_count
    }

    // Update session
    const { data, error } = await supabase
      .from('scan_sessions')
      .update(updateData)
      .eq('id', id)
      .select()
      .single()

    if (error) {
      console.error('Database error:', error)
      return json({ error: error.message }, 500)
    }

    if (!data) {
      return json({
        error: 'Session not found'
      }, 404)
    }

    return json({
      success: true,
      session: data
    }, 200)

  } catch (error) {
    console.error('Error completing session:', error)
    return json({
      error: error instanceof Error ? error.message : 'Internal server error'
    }, 500)
  }
})
