-- Execute no SQL Editor do Supabase. Cadastre admins inserindo o UUID de auth.users.
create extension if not exists pgcrypto;
create table public.events (
 id uuid primary key default gen_random_uuid(), name text not null, slug text,
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

create or replace function public.slugify_event_name(event_name text)
returns text
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    nullif(trim(both '-' from regexp_replace(
      translate(lower(trim(event_name)), U&'\00e1\00e0\00e2\00e3\00e4\00e9\00e8\00ea\00eb\00ed\00ec\00ee\00ef\00f3\00f2\00f4\00f5\00f6\00fa\00f9\00fb\00fc\00e7\00f1', 'aaaaaeeeeiiiiooooouuuucn'),
      '[^a-z0-9]+', '-', 'g'
    )), ''),
    'evento'
  );
$$;

create or replace function public.assign_event_slug()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  base_slug text;
begin
  if tg_op = 'INSERT' then
    base_slug := public.slugify_event_name(coalesce(nullif(new.slug, ''),new.name));
  elsif new.slug is distinct from old.slug or nullif(new.slug, '') is null then
    base_slug := public.slugify_event_name(coalesce(nullif(new.slug, ''),new.name));
  else
    return new;
  end if;
  if exists (
    select 1 from public.events e
    where e.slug = base_slug and e.id is distinct from new.id
  ) then
    base_slug := base_slug || '-' || substr(replace(new.id::text, '-', ''), 1, 6);
    if exists (
      select 1 from public.events e
      where e.slug = base_slug and e.id is distinct from new.id
    ) then
      base_slug := base_slug || '-' || replace(new.id::text, '-', '');
    end if;
  end if;
  new.slug := base_slug;
  return new;
end;
$$;

-- Generate a unique readable slug for each event.
with bases as (
  select id,coalesce(nullif(public.slugify_event_name(name),''),'evento') as base_slug,created_at
  from public.events
), numbered as (
  select id,base_slug,row_number() over(partition by base_slug order by created_at,id) as position
  from bases
)
update public.events e set slug=case when n.position=1 then n.base_slug else n.base_slug||'-'||substr(replace(n.id::text,'-',''),1,6) end
from numbered n where n.id=e.id;

alter table public.events alter column slug set not null;
create unique index if not exists events_slug_uidx on public.events(slug);
drop trigger if exists events_assign_slug on public.events;
create trigger events_assign_slug before insert or update of slug on public.events
for each row execute function public.assign_event_slug();

alter table public.events enable row level security;
alter table public.admins enable row level security;
alter table public.categories enable row level security;
alter table public.guests enable row level security;
alter table public.gifts enable row level security;
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = '' as 'select exists(select 1 from public.admins where user_id=auth.uid())';
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to anon,authenticated;

create policy "public reads active events" on public.events for select to anon, authenticated using (active or public.is_admin());

create policy "admins manage events" on public.events for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admins manage categories" on public.categories for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "public reads categories for active events" on public.categories for select to anon,authenticated using (exists(select 1 from public.events e where e.id=event_id and e.active) or public.is_admin());
create policy "admins manage gifts" on public.gifts for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "public reads available gifts" on public.gifts for select to anon,authenticated using (not reserved and exists(select 1 from public.events e where e.id=event_id and e.active));
create policy "admins read guests" on public.guests for select to authenticated using (public.is_admin());
create policy "admins manage guests" on public.guests for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admins can verify own membership" on public.admins for select to authenticated using (user_id=auth.uid());
revoke all on public.admins from anon,authenticated;
grant select on public.admins to authenticated;
grant select on public.events,public.categories,public.gifts to anon,authenticated;
grant all on public.events,public.categories,public.gifts to authenticated;
grant select,insert,update,delete on public.guests to authenticated;

create or replace function public.reserve_gifts(p_event_id uuid,p_name text,p_phone text,p_gift_ids uuid[])
returns jsonb language plpgsql security definer set search_path = '' as $$
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
