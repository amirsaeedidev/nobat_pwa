-- This is a database event-trigger function, not a client RPC.
-- Do not expose SECURITY DEFINER execution to API roles.
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
