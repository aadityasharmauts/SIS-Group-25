import { corsHeaders, json } from '../_shared/cors.ts';
import { requireUser } from '../_shared/supabase.ts';

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') {
    return json({ data: null, error: { code: 'method_not_allowed', message: 'Use POST for matching suggestions.' } }, 405);
  }

  const { client, user } = await requireUser(request);
  if (!client || !user) {
    return json({ data: null, error: { code: 'unauthorized', message: 'Sign in to view matching suggestions.' } }, 401);
  }

  const { data: verified, error: verificationError } = await client.rpc('is_verified_user', {
    p_user_id: user.id,
  });
  if (verificationError) {
    return json({ data: null, error: { code: 'matching_unavailable', message: 'Matching suggestions are temporarily unavailable.' } }, 500);
  }
  if (!verified) {
    return json({ data: null, error: { code: 'not_verified', message: 'Verify your organisation email to view matching suggestions.' } }, 403);
  }

  const { data, error } = await client.rpc('matching_suggestions', {
    p_user_id: user.id,
  });

  if (error) {
    console.error('refresh-suggestions failed:', error.message);
    return json({ data: null, error: { code: 'matching_unavailable', message: 'Matching suggestions are temporarily unavailable.' } }, 500);
  }
  return json({ data: data ?? [], error: null });
});
