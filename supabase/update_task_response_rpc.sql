-- Secure RPC for editing completed task responses.
-- Run this file once in Supabase SQL Editor before using the updated web UI.

create or replace function public.update_task_response(
  p_task_id uuid,
  p_response text,
  p_responded_at timestamptz default null
)
returns public.tasks
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task public.tasks%rowtype;
  v_result public.tasks%rowtype;
  v_is_admin boolean := false;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select *
    into v_task
    from public.tasks
   where id = p_task_id
     and deleted_at is null;

  if not found then
    raise exception 'Task not found' using errcode = 'P0002';
  end if;

  if v_task.status <> 'done' then
    raise exception 'Only completed responses can be edited' using errcode = '22023';
  end if;

  select coalesce(p.system_role = 'admin', false)
    into v_is_admin
    from public.profiles p
   where p.id = auth.uid()
     and p.is_active = true;

  if not v_is_admin and v_task.responded_by is distinct from auth.uid() then
    raise exception 'You may edit only your own response' using errcode = '42501';
  end if;

  if nullif(btrim(p_response), '') is null then
    raise exception 'Response cannot be blank' using errcode = '22023';
  end if;

  update public.tasks
     set response = btrim(p_response),
         responded_at = coalesce(p_responded_at, responded_at),
         task_data = coalesce(task_data, '{}'::jsonb)
           || jsonb_build_object(
                'response', btrim(p_response),
                'respondedAt', coalesce(p_responded_at, responded_at)
              ),
         updated_at = now()
   where id = p_task_id
  returning * into v_result;

  return v_result;
end;
$$;

revoke all on function public.update_task_response(uuid, text, timestamptz) from public;
grant execute on function public.update_task_response(uuid, text, timestamptz) to authenticated;
