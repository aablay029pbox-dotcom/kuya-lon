-- =========================================================
-- COSTruct — Full Supabase schema
-- Run this in: Supabase Dashboard → SQL Editor
-- =========================================================

-- 1) PROFILES (linked to auth.users)
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  name        text not null,
  role        text not null check (role in ('buyer','supplier')),
  contact     text,
  address     text,
  created_at  timestamptz not null default now()
);

-- 2) SUPPLIERS (business info for role='supplier')
create table if not exists public.suppliers (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid unique references auth.users(id) on delete cascade,
  email          text unique not null,
  name           text not null,                 -- business / store name
  owner_name     text,
  category       text not null check (category in ('construction','hardware','lumber','cement')),
  location       text not null,
  contact        text,
  address        text,
  description    text,
  since          text,
  delivery       text default 'Available',
  rating         numeric default 0,
  profile_views  integer default 0,
  created_at     timestamptz not null default now()
);

create index if not exists suppliers_location_idx on public.suppliers(location);
create index if not exists suppliers_category_idx on public.suppliers(category);

-- 3) MATERIALS (supplier catalog items)
create table if not exists public.materials (
  id           uuid primary key default gen_random_uuid(),
  supplier_id  uuid not null references public.suppliers(id) on delete cascade,
  name         text not null,
  price        numeric not null,
  unit         text not null,
  description  text,
  category     text,            -- cement, steel, lumber, hardware, paint, electrical, plumbing
  qty          integer,         -- optional stock count
  stock        text,            -- optional stock status string
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists materials_supplier_idx on public.materials(supplier_id);

-- 4) ESTIMATES (saved by logged-in buyers)
create table if not exists public.estimates (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  name        text not null,
  total       text,
  area        text,
  floors      integer,
  supplier    text,
  breakdown   text,
  saved_at    text,
  created_at  timestamptz not null default now()
);

create index if not exists estimates_user_idx on public.estimates(user_id);

-- =========================================================
-- ROW LEVEL SECURITY
-- =========================================================
alter table public.profiles  enable row level security;
alter table public.suppliers enable row level security;
alter table public.materials enable row level security;
alter table public.estimates enable row level security;

-- PROFILES: owner-only
create policy "profiles_select_self" on public.profiles
  for select using (auth.uid() = id);
create policy "profiles_insert_self" on public.profiles
  for insert with check (auth.uid() = id);
create policy "profiles_update_self" on public.profiles
  for update using (auth.uid() = id);

-- SUPPLIERS: public read, owner write
create policy "suppliers_public_read" on public.suppliers
  for select using (true);
create policy "suppliers_insert_self" on public.suppliers
  for insert with check (auth.uid() = user_id);
create policy "suppliers_update_self" on public.suppliers
  for update using (auth.uid() = user_id);
create policy "suppliers_delete_self" on public.suppliers
  for delete using (auth.uid() = user_id);

-- MATERIALS: public read, owning-supplier write
create policy "materials_public_read" on public.materials
  for select using (true);
create policy "materials_write_own" on public.materials
  for all
  using (
    exists (select 1 from public.suppliers s
            where s.id = supplier_id and s.user_id = auth.uid())
  )
  with check (
    exists (select 1 from public.suppliers s
            where s.id = supplier_id and s.user_id = auth.uid())
  );

-- ESTIMATES: owner-only
create policy "estimates_select_own" on public.estimates
  for select using (auth.uid() = user_id);
create policy "estimates_insert_own" on public.estimates
  for insert with check (auth.uid() = user_id);
create policy "estimates_delete_own" on public.estimates
  for delete using (auth.uid() = user_id);

-- =========================================================
-- REALTIME
-- =========================================================
alter publication supabase_realtime add table public.suppliers;
alter publication supabase_realtime add table public.materials;

-- =========================================================
-- Trigger: keep materials.updated_at fresh
-- =========================================================
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists materials_touch on public.materials;
create trigger materials_touch
before update on public.materials
for each row execute procedure public.touch_updated_at();

-- =========================================================
-- RPC: increment_profile_views
-- Lets any visitor bump the profile_views counter on a supplier row.
-- SECURITY DEFINER so it bypasses the "owner-only update" RLS rule
-- but only for this single counter field.
-- =========================================================
create or replace function public.increment_profile_views(supplier_email text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.suppliers
     set profile_views = coalesce(profile_views, 0) + 1
   where email = supplier_email;
end;
$$;

-- Allow anyone (including anon) to call it
grant execute on function public.increment_profile_views(text) to anon, authenticated;
