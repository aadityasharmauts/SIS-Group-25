import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

export function userClient(request: Request) {
  const authorization = request.headers.get('Authorization');
  if (!authorization) return null;

  return createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    { global: { headers: { Authorization: authorization } } },
  );
}

export async function requireUser(request: Request) {
  const client = userClient(request);
  if (!client) return { client: null, user: null };

  const { data: { user }, error } = await client.auth.getUser();
  if (error || !user) return { client, user: null };
  return { client, user };
}
