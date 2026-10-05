-- Execute no SQL Editor do Supabase para habilitar URLs legíveis em projetos existentes.
alter table public.events add column if not exists slug text;

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

do $$
declare
  event_row record;
  generated_slug text;
begin
  for event_row in
    select id,name from public.events
    where nullif(btrim(slug),'') is null
    order by created_at,id
  loop
    generated_slug := public.slugify_event_name(event_row.name);
    if exists (select 1 from public.events e where e.slug = generated_slug) then
      generated_slug := generated_slug || '-' || substr(replace(event_row.id::text,'-',''),1,6);
      if exists (select 1 from public.events e where e.slug = generated_slug) then
        generated_slug := generated_slug || '-' || replace(event_row.id::text,'-','');
      end if;
    end if;
    update public.events set slug=generated_slug where id=event_row.id;
  end loop;
end;
$$;

alter table public.events alter column slug set not null;
create unique index if not exists events_slug_uidx on public.events(slug);
drop trigger if exists events_assign_slug on public.events;
create trigger events_assign_slug before insert or update of slug on public.events
for each row execute function public.assign_event_slug();
