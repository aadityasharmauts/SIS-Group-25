import { corsHeaders, json } from '../_shared/cors.ts';
import { requireUser } from '../_shared/supabase.ts';

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const { client, user } = await requireUser(request);
  if (!client || !user) return json({ error: 'Authentication required' }, 401);

  try {
    const body = await request.json();
    const payload = {
      organisation_id: body.organisation_id,
      creator_id: user.id,
      title: typeof body.title === 'string' ? body.title.trim() : body.title,
      description: typeof body.description === 'string' ? body.description.trim() || null : null,
      location_id: body.location_id,
      area_id: body.area_id ?? null,
      latitude: body.latitude ?? null,
      longitude: body.longitude ?? null,
      start_time: body.start_time,
      end_time: body.end_time,
      status: body.status ?? 'draft',
    };

    const { data, error } = await client
      .from('official_events')
      .insert(payload)
      .select()
      .single();

    if (error) return json({ error: error.message }, 400);
    return json({ data }, 201);
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : 'Invalid request' }, 400);
  }
});
