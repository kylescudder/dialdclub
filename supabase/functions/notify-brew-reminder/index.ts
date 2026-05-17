type DeviceToken = {
  apns_token: string
  bundle_id: string
  environment: 'sandbox' | 'production'
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('method not allowed', { status: 405 })
  }

  const { user_id, title = 'BrewLab', body = 'Time to log a brew.' } = await req.json()
  if (!user_id) {
    return Response.json({ error: 'missing user_id' }, { status: 400 })
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !serviceKey) {
    return Response.json({ error: 'missing supabase env' }, { status: 500 })
  }

  const tokenResponse = await fetch(
    supabaseUrl + '/rest/v1/device_tokens?user_id=eq.' + user_id + '&deleted_at=is.null&select=apns_token,bundle_id,environment',
    { headers: { apikey: serviceKey, authorization: 'Bearer ' + serviceKey } },
  )
  const tokens = await tokenResponse.json() as DeviceToken[]

  // Placeholder fan-out hook. Self-hosted deployments can wire this to APNs using
  // APNS_TEAM_ID/APNS_KEY_ID/APNS_PRIVATE_KEY, matching the Deadwax pattern.
  console.log(JSON.stringify({ title, body, recipients: tokens.length }))
  return Response.json({ ok: true, recipients: tokens.length })
})
