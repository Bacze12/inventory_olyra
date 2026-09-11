-- ============================================================================
-- BodegaFlow POS · Módulo cloud (Supabase)
-- ----------------------------------------------------------------------------
-- Requiere que ya existan las tablas base de la plataforma:
--   apps(id, name, ...)
--   user_apps(id, user_id, app_id, is_active)
--   licenses(id, user_app_id, license_key, hardware_id, status, expires_at)
--
-- Ejecutar en el SQL Editor de tu proyecto (o como migración) UNA sola vez.
-- Todo el acceso está protegido por Row Level Security (RLS) con auth.uid():
-- el cliente anónimo SOLO puede leer/escribir filas cuya `user_app_id`
-- pertenezca al usuario autenticado.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Tablas del POS (alcance por `user_app_id` = la "bodega"/entitlement)
-- ---------------------------------------------------------------------------

-- Catálogo + stock. `barcode` único POR BODEGA (multi-dispositivo LWW se
-- resuelve en cliente con `updated_at`: gana la fila más reciente).
create table if not exists public.pos_products (
  id           uuid primary key default gen_random_uuid(),
  user_app_id  uuid not null references public.user_apps(id) on delete cascade,
  barcode      text not null,
  name         text not null,
  quantity     integer not null default 0 check (quantity >= 0),
  min_stock    integer not null default 0,
  price        numeric(12,2) not null default 0,
  image_path   text,
  updated_by   text not null default '',          -- hardware_id del origen
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (user_app_id, barcode)
);

create index if not exists idx_pos_products_barcode
  on public.pos_products (user_app_id, barcode);
create index if not exists idx_pos_products_updated
  on public.pos_products (user_app_id, updated_at);

-- Movimientos de stock (entradas/salidas). Se guarda el `barcode` (denorm.)
-- para conservar el historial aunque el producto se elimine.
create table if not exists public.pos_movements (
  id             uuid primary key default gen_random_uuid(),
  user_app_id    uuid not null references public.user_apps(id) on delete cascade,
  barcode        text not null,
  type           text not null check (type in ('IN', 'OUT')),
  delta          integer not null check (delta >= 0),
  quantity_after integer not null check (quantity_after >= 0),
  created_at     timestamptz not null default now()
);

create index if not exists idx_pos_movements
  on public.pos_movements (user_app_id, created_at);

-- Ventas (cabecera). `local_id` = id del SQLite local + unique por bodega:
-- esto hace el push IDEMPOTENTE (reintentos/upserts no duplican).
create table if not exists public.pos_sales (
  id                 uuid primary key default gen_random_uuid(),
  user_app_id        uuid not null references public.user_apps(id) on delete cascade,
  local_id           bigint not null,
  device_hardware_id text not null default '',
  payment_method     text not null default 'Efectivo'
    check (payment_method in ('Efectivo', 'Tarjeta')),
  subtotal           numeric(12,2) not null default 0,
  tax_rate           numeric(6,4)  not null default 0,
  tax_amount         numeric(12,2) not null default 0,
  total              numeric(12,2) not null default 0,
  received           numeric(12,2),
  change             numeric(12,2) not null default 0,
  status             text not null default 'Completada'
    check (status in ('Completada', 'Anulada')),
  stock_warning      boolean not null default false,
  created_at         timestamptz not null default now(),
  unique (user_app_id, local_id)
);

create index if not exists idx_pos_sales
  on public.pos_sales (user_app_id, created_at);

-- Líneas del ticket (snapshot de la venta).
create table if not exists public.pos_sale_items (
  id            uuid primary key default gen_random_uuid(),
  sale_id       uuid not null references public.pos_sales(id) on delete cascade,
  barcode       text,
  product_name  text not null,
  unit_price    numeric(12,2) not null default 0,
  quantity      integer not null default 1,
  subtotal      numeric(12,2) not null default 0
);

create index if not exists idx_pos_sale_items_sale
  on public.pos_sale_items (sale_id);

-- ---------------------------------------------------------------------------
-- 2. Licencia: validación de dispositivo
-- ---------------------------------------------------------------------------
-- Función SECURITY DEFINER: ejecuta con privilegios del dueño para leer la
-- tabla `licenses` (RLS de esa tabla no se aplica aquí), PERO la restringimos
-- explícitamente a `auth.uid()` para que un usuario solo pueda validar SUS
-- propias licencias. Devuelve cero filas si el hardware no está autorizado.
create or replace function public.fn_validate_device(p_hardware_id text)
returns table (
  valid       boolean,
  license_key text,
  status      text,
  expires_at  timestamptz,
  app_name    text,
  user_app_id uuid
)
language sql
security definer
set search_path = public
as $$
  select
    (l.status = 'active'
      and (l.expires_at is null or l.expires_at > now())
      and ua.is_active) as valid,
    l.license_key,
    l.status,
    l.expires_at,
    a.name as app_name,
    l.user_app_id
  from public.licenses l
  join public.user_apps ua on ua.id = l.user_app_id
  join public.apps a     on a.id   = ua.app_id
  where l.hardware_id = p_hardware_id
    and ua.user_id = auth.uid();
$$;

revoke all on function public.fn_validate_device(text) from public;
grant execute on function public.fn_validate_device(text) to authenticated;
grant execute on function public.fn_validate_device(text) to anon;

-- ---------------------------------------------------------------------------
-- 3. Row Level Security
-- ---------------------------------------------------------------------------
alter table public.pos_products  enable row level security;
alter table public.pos_movements enable row level security;
alter table public.pos_sales     enable row level security;
alter table public.pos_sale_items enable row level security;

-- Usuario autenticado: solo filas de sus bodegas activas.
create policy "pos_products_select" on public.pos_products
  for select using (
    user_app_id in (select id from public.user_apps
                    where user_id = auth.uid() and is_active)
  );
create policy "pos_products_insert" on public.pos_products
  for insert with check (
    user_app_id in (select id from public.user_apps
                    where user_id = auth.uid() and is_active)
  );
create policy "pos_products_update" on public.pos_products
  for update using (
    user_app_id in (select id from public.user_apps
                    where user_id = auth.uid() and is_active)
  ) with check (
    user_app_id in (select id from public.user_apps
                    where user_id = auth.uid() and is_active)
  );
create policy "pos_products_delete" on public.pos_products
  for delete using (
    user_app_id in (select id from public.user_apps
                    where user_id = auth.uid() and is_active)
  );

create policy "pos_movements_all" on public.pos_movements
  for all using (
    user_app_id in (select id from public.user_apps
                    where user_id = auth.uid() and is_active)
  ) with check (
    user_app_id in (select id from public.user_apps
                    where user_id = auth.uid() and is_active)
  );

create policy "pos_sales_select" on public.pos_sales
  for select using (
    user_app_id in (select id from public.user_apps
                    where user_id = auth.uid() and is_active)
  );
create policy "pos_sales_insert" on public.pos_sales
  for insert with check (
    user_app_id in (select id from public.user_apps
                    where user_id = auth.uid() and is_active)
  );
create policy "pos_sales_update" on public.pos_sales
  for update using (
    user_app_id in (select id from public.user_apps
                    where user_id = auth.uid() and is_active)
  ) with check (
    user_app_id in (select id from public.user_apps
                    where user_id = auth.uid() and is_active)
  );

create policy "pos_sale_items_select" on public.pos_sale_items
  for select using (
    exists (select 1 from public.pos_sales s
            where s.id = sale_id
              and s.user_app_id in (select id from public.user_apps
                                    where user_id = auth.uid() and is_active))
  );
create policy "pos_sale_items_insert" on public.pos_sale_items
  for insert with check (
    exists (select 1 from public.pos_sales s
            where s.id = sale_id
              and s.user_app_id in (select id from public.user_apps
                                    where user_id = auth.uid() and is_active))
  );

-- Nota: `pos_sales` NO tiene policy de delete a propósito: una venta registrada
-- en la nube es inmutable (solo cambia `status` vía update).

-- ---------------------------------------------------------------------------
-- 4. Storage para respaldos
-- ---------------------------------------------------------------------------
-- Bucket privado; el path SIEMPRE va prefijado por el uid del usuario.
insert into storage.buckets (id, name, public)
values ('pos-backups', 'pos-backups', false)
on conflict (id) do nothing;

create policy "pos_backups_insert" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'pos-backups'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "pos_backups_read" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'pos-backups'
    and (storage.foldername(name))[1] = auth.uid()::text
  );