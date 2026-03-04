-- ============================================================
-- WELLTRACK PRO — Supabase Database Setup
-- Run this entire script in Supabase → SQL Editor → New Query
-- ============================================================

-- 1. DEALS table
create table if not exists deals (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  location text,
  formation text,
  operator text,
  api_number text,
  status text default 'planning', -- planning | fundraising | permitted | drilling | completed
  target_depth text,
  raise_target numeric default 0,
  raise_committed numeric default 0,
  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- 2. PROMOTERS table (linked to Supabase auth users)
create table if not exists promoters (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users(id) on delete cascade,
  name text not null,
  company text,
  email text not null,
  created_at timestamptz default now()
);

-- 3. DEAL_PROMOTER_ACCESS — which promoters can see which deals
create table if not exists deal_access (
  id uuid default gen_random_uuid() primary key,
  deal_id uuid references deals(id) on delete cascade,
  promoter_id uuid references promoters(id) on delete cascade,
  granted_at timestamptz default now(),
  unique(deal_id, promoter_id)
);

-- 4. UPDATES — posted by admin, visible to assigned promoters
create table if not exists updates (
  id uuid default gen_random_uuid() primary key,
  deal_id uuid references deals(id) on delete cascade,
  update_type text not null, -- drilling | documents | regulatory | financial
  message text not null,
  attachment_name text,
  created_at timestamptz default now()
);

-- 5. DOCUMENTS
create table if not exists documents (
  id uuid default gen_random_uuid() primary key,
  deal_id uuid references deals(id) on delete cascade,
  name text not null,
  file_type text,
  doc_type text, -- Executive Summary | Isopach Map | Cross Section | AFE | Well Path | Other
  file_size text,
  url text,
  created_at timestamptz default now()
);

-- 6. AFE_ITEMS — budget line items per deal
create table if not exists afe_items (
  id uuid default gen_random_uuid() primary key,
  deal_id uuid references deals(id) on delete cascade,
  category text not null,
  budget numeric default 0,
  actual numeric default 0,
  sort_order int default 0
);

-- ── ADMIN USER ──────────────────────────────────────────────
-- We identify the admin by email stored here
create table if not exists admin_users (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users(id) on delete cascade,
  email text not null unique
);

-- ── ROW LEVEL SECURITY ──────────────────────────────────────

alter table deals enable row level security;
alter table promoters enable row level security;
alter table deal_access enable row level security;
alter table updates enable row level security;
alter table documents enable row level security;
alter table afe_items enable row level security;
alter table admin_users enable row level security;

-- Helper: is current user an admin?
create or replace function is_admin()
returns boolean language sql security definer as $$
  select exists (
    select 1 from admin_users where user_id = auth.uid()
  );
$$;

-- Helper: does current promoter have access to this deal?
create or replace function promoter_has_access(p_deal_id uuid)
returns boolean language sql security definer as $$
  select exists (
    select 1 from deal_access da
    join promoters p on p.id = da.promoter_id
    where da.deal_id = p_deal_id
    and p.user_id = auth.uid()
  );
$$;

-- DEALS: admin full access, promoters read only their assigned deals
create policy "admin_all_deals" on deals for all using (is_admin());
create policy "promoter_read_deals" on deals for select
  using (promoter_has_access(id));

-- PROMOTERS: admin full access, promoter can read their own row
create policy "admin_all_promoters" on promoters for all using (is_admin());
create policy "promoter_read_self" on promoters for select
  using (user_id = auth.uid());

-- DEAL_ACCESS: admin only
create policy "admin_all_access" on deal_access for all using (is_admin());
create policy "promoter_read_own_access" on deal_access for select
  using (exists (select 1 from promoters p where p.id = promoter_id and p.user_id = auth.uid()));

-- UPDATES: admin full, promoters read assigned
create policy "admin_all_updates" on updates for all using (is_admin());
create policy "promoter_read_updates" on updates for select
  using (promoter_has_access(deal_id));

-- DOCUMENTS: admin full, promoters read assigned
create policy "admin_all_docs" on documents for all using (is_admin());
create policy "promoter_read_docs" on documents for select
  using (promoter_has_access(deal_id));

-- AFE: admin full, promoters read assigned
create policy "admin_all_afe" on afe_items for all using (is_admin());
create policy "promoter_read_afe" on afe_items for select
  using (promoter_has_access(deal_id));

-- ADMIN_USERS: admin only
create policy "admin_read_self" on admin_users for select using (user_id = auth.uid());

-- ── SAMPLE DATA (optional — delete if you want a clean start) ──
insert into deals (name, location, formation, operator, api_number, status, target_depth, raise_target, raise_committed, notes) values
('Permian Basin #7', 'Midland Co., TX', 'Spraberry / Wolfcamp', 'Basin Resources LLC', '42-329-40801', 'drilling', '9,200 ft', 4000000, 3200000, 'Spud confirmed. Currently at 7,800 ft.'),
('Eagle Ford Unit 3', 'Karnes Co., TX', 'Eagle Ford Shale', 'South Texas E&P', '42-255-33021', 'fundraising', '7,800 ft', 3500000, 1800000, 'Exec summary distributed. Awaiting final LP commitments.'),
('Haynesville South', 'DeSoto Parish, LA', 'Haynesville Shale', 'Ark-La-Tex Petroleum', '17-031-20034', 'fundraising', '13,000 ft', 2800000, 900000, 'Isopach maps sent. Seismic review pending.');
