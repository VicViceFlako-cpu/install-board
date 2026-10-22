-- Door Pace setup for Install Board's Supabase project.
-- Paste into Supabase → SQL Editor → New query → Run. Safe to run once.

create table public.canvass_members(
  user_id uuid primary key references public.profiles(id) on delete cascade,
  display_name text not null,
  is_admin boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create table public.canvass_doors(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  surveys int not null check (surveys between 0 and 20),
  created_at timestamptz not null default now()
);
create index on public.canvass_doors(user_id, created_at);
create table public.canvass_shifts(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  started_at timestamptz not null,
  ended_at timestamptz not null default now(),
  houses int not null,
  surveys int not null,
  rate numeric not null
);
create index on public.canvass_shifts(user_id, ended_at desc);
create table public.canvass_settings(
  id int primary key default 1 check (id = 1),
  rate numeric not null default 3 check (rate > 0),
  goal numeric not null default 2 check (goal > 0),
  updated_at timestamptz not null default now()
);
insert into public.canvass_settings(id) values (1);

create or replace function public.canvass_is_member() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from canvass_members where user_id = auth.uid() and active)
$$;
create or replace function public.canvass_is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from canvass_members where user_id = auth.uid() and active and is_admin)
$$;

alter table public.canvass_members enable row level security;
alter table public.canvass_doors enable row level security;
alter table public.canvass_shifts enable row level security;
alter table public.canvass_settings enable row level security;

create policy cm_read on public.canvass_members for select to authenticated using (public.canvass_is_member());
create policy cd_read on public.canvass_doors for select to authenticated using (user_id = auth.uid() or public.canvass_is_admin());
create policy cd_insert on public.canvass_doors for insert to authenticated with check (user_id = auth.uid() and public.canvass_is_member());
create policy cd_delete on public.canvass_doors for delete to authenticated using (user_id = auth.uid() and public.canvass_is_member());
create policy cs_read on public.canvass_shifts for select to authenticated using (user_id = auth.uid() or public.canvass_is_admin());
create policy cset_read on public.canvass_settings for select to authenticated using (public.canvass_is_member());
create policy cset_update on public.canvass_settings for update to authenticated using (public.canvass_is_admin()) with check (public.canvass_is_admin());

create or replace function public.canvass_end_shift() returns public.canvass_shifts
language plpgsql security definer set search_path = public as $$
declare r canvass_shifts; h int; s int; st timestamptz; rt numeric;
begin
  if not canvass_is_member() then raise exception 'not a member'; end if;
  select count(*), coalesce(sum(surveys),0), min(created_at) into h, s, st from canvass_doors where user_id = auth.uid();
  if h = 0 then raise exception 'no doors logged'; end if;
  select rate into rt from canvass_settings where id = 1;
  insert into canvass_shifts(user_id, started_at, houses, surveys, rate) values (auth.uid(), st, h, s, rt) returning * into r;
  delete from canvass_doors where user_id = auth.uid();
  return r;
end $$;

create or replace function public.canvass_leaderboard() returns table(user_id uuid, display_name text, cur_houses int, cur_surveys int, week_houses int, week_surveys int)
language sql stable security definer set search_path = public as $$
  with wk as (select (date_trunc('week', now() at time zone 'America/New_York') at time zone 'America/New_York') as start)
  select m.user_id, m.display_name,
    coalesce((select count(*) from canvass_doors d where d.user_id = m.user_id),0)::int,
    coalesce((select sum(surveys) from canvass_doors d where d.user_id = m.user_id),0)::int,
    (coalesce((select count(*) from canvass_doors d where d.user_id = m.user_id),0)
      + coalesce((select sum(houses) from canvass_shifts s, wk where s.user_id = m.user_id and s.ended_at >= wk.start),0))::int,
    (coalesce((select sum(surveys) from canvass_doors d where d.user_id = m.user_id),0)
      + coalesce((select sum(surveys) from canvass_shifts s, wk where s.user_id = m.user_id and s.ended_at >= wk.start),0))::int
  from canvass_members m
  where m.active and canvass_is_member()
$$;

revoke all on function public.canvass_end_shift() from public, anon;
revoke all on function public.canvass_leaderboard() from public, anon;
revoke all on function public.canvass_is_member() from public, anon;
revoke all on function public.canvass_is_admin() from public, anon;
grant execute on function public.canvass_end_shift() to authenticated;
grant execute on function public.canvass_leaderboard() to authenticated;
grant execute on function public.canvass_is_member() to authenticated;
grant execute on function public.canvass_is_admin() to authenticated;

insert into public.canvass_members(user_id, display_name, is_admin) values
  ('8209813c-c1c6-480a-9e5a-d43d4fe2c31f','Victor',true),
  ('263df869-02b1-4d18-848c-0b6a62ea7060','Cordell',false),
  ('c95732d6-6783-4f82-95db-84b59a5169d9','Kristopher',false);
