-- Execute no SQL Editor do Supabase. Cadastre admins inserindo o UUID de auth.users.
create extension if not exists pgcrypto;
create table public.events (
 id uuid primary key default gen_random_uuid(), name text not null,
 event_date date, event_time time, address text not null default '', final_message text not null default '',
 active boolean not null default true, created_at timestamptz not null default now()
);
create table public.admins (user_id uuid primary key references auth.users(id) on delete cascade);
create table public.categories (
 id uuid primary key default gen_random_uuid(), event_id uuid not null references public.events(id) on delete cascade,
 name text not null, sort_order integer not null default 0, unique(event_id,name)
);
create table public.guests (
 id uuid primary key default gen_random_uuid(), event_id uuid not null references public.events(id) on delete cascade,
 name text not null, phone text not null, unique(event_id,name,phone)
);
create table public.gifts (
 id uuid primary key default gen_random_uuid(), event_id uuid not null references public.events(id) on delete cascade,
 category_id uuid references public.categories(id) on delete set null, name text not null,
 reserved boolean not null default false, reserved_by uuid references public.guests(id) on delete set null,
 created_at timestamptz not null default now(),
 constraint gift_reservation_consistent check ((reserved and reserved_by is not null) or (not reserved and reserved_by is null))
);
create index gifts_event_category_idx on public.gifts(event_id,category_id);
create index gifts_reserved_by_idx on public.gifts(reserved_by);

alter table public.events enable row level security;
alter table public.admins enable row level security;
alter table public.categories enable row level security;
alter table public.guests enable row level security;
alter table public.gifts enable row level security;
create policy "public reads active events" on public.events for select to anon, authenticated using (active or exists(select 1 from public.admins where user_id=auth.uid()));
create policy "admins manage events" on public.events for all to authenticated using (exists(select 1 from public.admins where user_id=auth.uid())) with check (exists(select 1 from public.admins where user_id=auth.uid()));
create policy "admins manage categories" on public.categories for all to authenticated using (exists(select 1 from public.admins where user_id=auth.uid())) with check (exists(select 1 from public.admins where user_id=auth.uid()));
create policy "public reads categories for active events" on public.categories for select to anon,authenticated using (exists(select 1 from public.events e where e.id=event_id and e.active) or exists(select 1 from public.admins where user_id=auth.uid()));
create policy "admins manage gifts" on public.gifts for all to authenticated using (exists(select 1 from public.admins where user_id=auth.uid())) with check (exists(select 1 from public.admins where user_id=auth.uid()));
create policy "public reads available gifts" on public.gifts for select to anon,authenticated using (not reserved and exists(select 1 from public.events e where e.id=event_id and e.active));
create policy "admins read guests" on public.guests for select to authenticated using (exists(select 1 from public.admins where user_id=auth.uid()));
create policy "admins manage guests" on public.guests for all to authenticated using (exists(select 1 from public.admins where user_id=auth.uid())) with check (exists(select 1 from public.admins where user_id=auth.uid()));
create policy "admins can verify own membership" on public.admins for select to authenticated using (user_id=auth.uid());
revoke all on public.admins from anon,authenticated;
grant select on public.admins to authenticated;
grant select on public.events,public.categories,public.gifts to anon,authenticated;
grant all on public.events,public.categories,public.gifts to authenticated;
grant select,insert,update,delete on public.guests to authenticated;

create or replace function public.reserve_gifts(p_event_id uuid,p_name text,p_phone text,p_gift_ids uuid[])
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_guest_id uuid; v_count integer; v_expected integer;
begin
 if nullif(trim(p_name),'') is null or nullif(trim(p_phone),'') is null then raise exception 'Informe nome e telefone.'; end if;
 if coalesce(array_length(p_gift_ids,1),0)=0 then raise exception 'Selecione ao menos um presente.'; end if;
 if (select count(distinct x) from unnest(p_gift_ids) x) <> array_length(p_gift_ids,1) then raise exception 'Há presentes repetidos.'; end if;
 if not exists(select 1 from public.events where id=p_event_id and active) then raise exception 'Evento indisponível.'; end if;
 v_expected := array_length(p_gift_ids,1);
 insert into public.guests(event_id,name,phone) values(p_event_id,trim(p_name),trim(p_phone))
 on conflict(event_id,name,phone) do update set name=excluded.name returning id into v_guest_id;
 -- A atualização condicional serializa a disputa: cada linha só pode ser reservada uma vez.
 update public.gifts set reserved=true,reserved_by=v_guest_id where id=any(p_gift_ids) and event_id=p_event_id and reserved=false;
 get diagnostics v_count = row_count;
 if v_count <> v_expected then raise exception 'Um ou mais presentes acabaram de ser reservados. Atualize a lista e tente novamente.'; end if;

 return jsonb_build_object('guest_id',v_guest_id,'reserved_count',v_count);
end; $$;
revoke all on function public.reserve_gifts(uuid,text,text,uuid[]) from public;
grant execute on function public.reserve_gifts(uuid,text,text,uuid[]) to anon,authenticated;


