-- ============================================================================
-- BodegaFlow POS · Módulo Turnos y Cajas (Supabase)
-- ----------------------------------------------------------------------------
-- Extiende 0001_bodegaflow_cloud.sql con el respaldo de `pos_shifts`.
--
-- Los turnos viven en SQLite con ids locales (INTEGER AUTOINCREMENT) y se
-- suben aquí con `local_id` texto + único por bodega → push idempotente.
-- `register_id`/`cashier_id` NO llevan FK a proposito: son ids de las cajas y
-- cajeros SQLite locales; el respaldo funciona aunque esas filas no existan.
--
-- Ejecutar UNA sola vez en el SQL Editor del proyecto (o como migración).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Tabla de turnos
-- ---------------------------------------------------------------------------
create table if not exists public.pos_shifts (
  id             uuid primary key default gen_random_uuid(),
  user_app_id    uuid not null references public.user_apps(id) on delete cascade,
  local_id       text not null,
  register_id    text not null default 'caja-1',
  cashier_id     text,
  opening_amount numeric(12,2) not null default 0,
  closing_amount numeric(12,2),
  expected_amount numeric(12,2),
  status         text not null default 'abierto'
    check (status in ('abierto', 'cerrado')),
  opened_at      timestamptz not null default now(),
  closed_at      timestamptz,
  created_at     timestamptz not null default now(),
  unique (user_app_id, local_id)
);

create index if not exists idx_pos_shifts_user
  on public.pos_shifts (user_app_id, opened_at);
create index if not exists idx_pos_shifts_register
  on public.pos_shifts (user_app_id, register_id, opened_at);

-- ---------------------------------------------------------------------------
-- 2. Ventas → turno (asociación opcional, denormalizada)
-- ---------------------------------------------------------------------------
-- `shift_id` texto con el local_id del turno SQLite; sin FK para conservar el
-- esquema publicado y no romper filas históricas (backfill).
alter table public.pos_sales
  add column if not exists shift_id text;

create index if not exists idx_pos_sales_shift
  on public.pos_sales (user_app_id, shift_id);

-- ---------------------------------------------------------------------------
-- 3. Row Level Security (turnos)
-- ---------------------------------------------------------------------------
alter table public.pos_shifts enable row level security;

create policy "pos_shifts_select" on public.pos_shifts
  for select using (
    user_app_id in (select id from public.user_apps
                    where user_id = auth.uid() and is_active)
  );
create policy "pos_shifts_insert" on public.pos_shifts
  for insert with check (
    user_app_id in (select id from public.user_apps
                    where user_id = auth.uid() and is_active)
  );
create policy "pos_shifts_update" on public.pos_shifts
  for update using (
    user_app_id in (select id from public.user_apps
                    where user_id = auth.uid() and is_active)
  ) with check (
    user_app_id in (select id from public.user_apps
                    where user_id = auth.uid() and is_active)
  );

-- Los turnos son inmutables: NO se definen policies de delete.