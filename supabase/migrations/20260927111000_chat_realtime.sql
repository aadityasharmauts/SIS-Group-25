-- live updates for chat (RLS still applies)

alter publication supabase_realtime add table public.conversations;
alter publication supabase_realtime add table public.messages;
