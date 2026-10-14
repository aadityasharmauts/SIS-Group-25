import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

// Fails fast with a legible message: createClient(undefined, undefined)
// throws an opaque "supabaseUrl is required" and blanks the whole app.
if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error(
    'Missing Supabase environment variables. Create a file named exactly ".env" ' +
      'at the project root, next to package.json, containing ' +
      'VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY. Then restart the dev server ' +
      '(Vite only reads .env at startup).'
  )
}

// Single shared Supabase client for the whole app.
// Only ever uses the public anon key here — the service_role key must
// never be bundled into frontend code (it bypasses Row Level Security).
export const supabase = createClient(supabaseUrl, supabaseAnonKey)
