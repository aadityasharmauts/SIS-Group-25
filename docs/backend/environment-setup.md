# Backend Environment Setup

Phase 0 deliverable: `.env.example` + this document.

## What these variables are for

Recess's frontend talks to Supabase directly (Supabase Auth, Postgres via
PostgREST, Realtime, Storage), protected by Row Level Security. Sensitive
actions (matching, event approval, blocking, reporting) go through Supabase
Edge Functions instead — see "Server-side / Edge Function secrets" below.

## One-time setup (each teammate does this locally)

1. Copy the template:
   ```bash
   cp .env.example .env
   ```
2. Get the project URL and anon key:
   - Ask whoever created the Supabase development project (Phase 0 —
     "Create Supabase development project") for the project, or open it
     yourself in the [Supabase dashboard](https://supabase.com/dashboard).
   - Go to **Project Settings -> API**.
   - Copy **Project URL** -> `VITE_SUPABASE_URL`.
   - Copy the **`anon` `public`** key -> `VITE_SUPABASE_ANON_KEY`.
     Do **not** copy the `service_role` key here.
3. Save `.env`. It's already listed in `.gitignore` — it will never be
   committed. Restart `npm run dev` after editing it (Vite only reads
   `.env` files at startup).

## Variable reference

| Variable | Where it's used | Safe for the browser? |
|---|---|---|
| `VITE_SUPABASE_URL` | `src/lib/supabaseClient.js` | Yes |
| `VITE_SUPABASE_ANON_KEY` | `src/lib/supabaseClient.js` | Yes — RLS is what actually protects data, not secrecy of this key |
| `VITE_MAPBOX_TOKEN` (pending) | map components, once a provider is chosen | Yes, if a public/scoped token |

Any variable prefixed `VITE_` is inlined into the client bundle at build
time and is visible to anyone using the app. Only ever put values here
that are safe to be public.

## Server-side / Edge Function secrets (not in this .env)

The `service_role` key and anything else that must bypass RLS is **never**
stored in this frontend `.env` or committed to the repo. The event Edge
Functions in this repository use the caller's JWT and do not require a
service-role key. If a future privileged function needs one, store it only in
Supabase's function secrets:

```bash
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=... 
```

Deploy the current event functions with:

```bash
supabase functions deploy create-activity
supabase functions deploy create-official-event
supabase functions deploy rsvp-to-event
```

For local development, run `supabase functions serve` alongside the Vite
server. The frontend falls back to the same RLS-protected PostgREST operation
when the local Edge Function runtime is not running.

## Using the client in code

```js
import { supabase } from '../lib/supabaseClient'

const { data, error } = await supabase.from('organisations').select('*')
```

## Troubleshooting

- **Blank page / console error "Missing Supabase environment variables"**:
  `.env` is missing or wasn't filled in — see step 1-2 above, then restart
  `npm run dev`.
- **401 / RLS errors on every query**: usually means the anon key or URL
  is wrong, or a table's RLS policy isn't set up yet.
