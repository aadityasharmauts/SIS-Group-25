import { corsHeaders, json } from '../_shared/cors.ts';
import { requireUser } from '../_shared/supabase.ts';

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const { client, user } = await requireUser(request);
  if (!client || !user) return json({ error: 'Authentication required' }, 401);

  try {
    const body = await request.json();
    if (!body.event_id || !['going', 'interested'].includes(body.status ?? 'going')) {
      return json({ error: 'event_id and a valid status are required' }, 400);
    }

    const { data, error } = await client
      .from('event_rsvps')
      .upsert({ event_id: body.event_id, user_id: user.id, status: body.status ?? 'going' }, { onConflict: 'event_id,user_id' })
      .select()
      .single();

    if (error) return json({ error: error.message }, 400);
    return json({ data });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : 'Invalid request' }, 400);
  }
});
