-- BNB Manager · Phase 1 core schema
-- Run in Supabase SQL editor or with `supabase db push`.
create extension if not exists pgcrypto;
create extension if not exists btree_gist;

create type public.app_role as enum ('owner','admin','manager','staff','accountant','shareholder');
create type public.apartment_status as enum ('active','inactive','maintenance');
create type public.booking_status as enum ('pending','confirmed','checked_in','checked_out','cancelled','no_show');
create type public.booking_source as enum ('airbnb','booking_com','agoda','facebook','zalo','direct','other');
create type public.payment_type as enum ('receipt','refund','deposit_received','deposit_refund','adjustment');
create type public.payment_method as enum ('cash','bank_transfer','card','platform','other');

create table public.tenants (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 160),
  created_at timestamptz not null default now()
);
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id),
  full_name text not null,
  email text not null,
  phone text,
  role public.app_role not null default 'staff',
  status text not null default 'active' check (status in ('active','suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index profiles_tenant_role_idx on public.profiles(tenant_id,role);

create table public.apartments (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id),
  code text not null, name text not null, building text, address text, floor integer,
  type text, bedrooms integer not null default 0 check (bedrooms >= 0),
  max_guests integer not null default 2 check (max_guests > 0),
  standard_checkin_time time not null default '14:00', standard_checkout_time time not null default '12:00',
  status public.apartment_status not null default 'active', monthly_rent numeric(14,0) not null default 0 check (monthly_rent>=0),
  management_fee numeric(14,0) not null default 0 check (management_fee>=0), notes text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(tenant_id,code), unique(tenant_id,id)
);
create index apartments_tenant_status_idx on public.apartments(tenant_id,status,code);

create table public.customers (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id),
  name text not null, phone text not null, email text, notes text, created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(tenant_id,id), unique(tenant_id,phone)
);
create index customers_tenant_phone_idx on public.customers(tenant_id,phone);

create table public.bookings (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id),
  apartment_id uuid not null, customer_id uuid not null, checkin_date date not null, checkout_date date not null,
  checkin_time time not null, checkout_time time not null, guest_count integer not null check (guest_count>0),
  source public.booking_source not null, status public.booking_status not null default 'confirmed',
  room_amount numeric(14,0) not null check (room_amount>=0), surcharge_amount numeric(14,0) not null default 0 check(surcharge_amount>=0),
  discount_amount numeric(14,0) not null default 0 check(discount_amount>=0), platform_fee numeric(14,0) not null default 0 check(platform_fee>=0),
  total_amount numeric(14,0) not null check(total_amount>=0), created_by uuid not null references public.profiles(id),
  assigned_to uuid references public.profiles(id), customer_note text, internal_note text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check(checkout_date>checkin_date), unique(tenant_id,id),
  foreign key(tenant_id,apartment_id) references public.apartments(tenant_id,id),
  foreign key(tenant_id,customer_id) references public.customers(tenant_id,id)
);
create index bookings_tenant_dates_idx on public.bookings(tenant_id,checkin_date,checkout_date);
create index bookings_apartment_dates_idx on public.bookings(apartment_id,checkin_date,checkout_date) where status <> 'cancelled';
create index bookings_tenant_status_idx on public.bookings(tenant_id,status);
alter table public.bookings add constraint bookings_no_overlapping_stays
  exclude using gist (apartment_id with =, daterange(checkin_date,checkout_date,'[)') with &&)
  where (status not in ('cancelled','no_show'));

-- One transaction creates/reuses the customer and writes the booking.
create or replace function public.create_booking_with_customer(
  p_apartment_id uuid,p_customer_name text,p_customer_phone text,p_customer_email text,p_customer_note text,
  p_checkin_date date,p_checkout_date date,p_checkin_time time,p_checkout_time time,p_guest_count integer,
  p_source public.booking_source,p_status public.booking_status,p_room_amount numeric,p_surcharge_amount numeric,p_discount_amount numeric
) returns uuid language plpgsql security definer set search_path=public
as $$
declare tenant uuid; customer uuid; booking uuid; capacity integer;
begin
  tenant=public.current_tenant_id();
  if auth.uid() is null or tenant is null or public.current_app_role() not in ('owner','admin','manager','staff') then
    raise insufficient_privilege using message='Not authorized to create a booking.';
  end if;
  if p_status not in ('pending','confirmed') then raise check_violation using message='New bookings must be pending or confirmed.'; end if;
  if p_checkin_date>=p_checkout_date then raise check_violation using message='Check-out must be after check-in.'; end if;
  if p_guest_count<=0 or p_room_amount<0 or p_surcharge_amount<0 or p_discount_amount<0 or p_room_amount+p_surcharge_amount<p_discount_amount then
    raise check_violation using message='Booking amounts or guest count are invalid.';
  end if;
  select max_guests into capacity from public.apartments where id=p_apartment_id and tenant_id=tenant and status='active';
  if not found then raise no_data_found using message='Active apartment not found.'; end if;
  if p_guest_count>capacity then raise check_violation using message='Guest count exceeds apartment capacity.'; end if;
  insert into public.customers(tenant_id,name,phone,email,notes,created_by)
  values(tenant,trim(p_customer_name),trim(p_customer_phone),nullif(trim(coalesce(p_customer_email,'')),''),nullif(trim(coalesce(p_customer_note,'')),''),auth.uid())
  on conflict(tenant_id,phone) do nothing returning id into customer;
  if customer is null then select id into customer from public.customers where tenant_id=tenant and phone=trim(p_customer_phone); end if;
  insert into public.bookings(tenant_id,apartment_id,customer_id,checkin_date,checkout_date,checkin_time,checkout_time,guest_count,source,status,room_amount,surcharge_amount,discount_amount,total_amount,created_by,customer_note)
  values(tenant,p_apartment_id,customer,p_checkin_date,p_checkout_date,p_checkin_time,p_checkout_time,p_guest_count,p_source,p_status,p_room_amount,p_surcharge_amount,p_discount_amount,p_room_amount+p_surcharge_amount-p_discount_amount,auth.uid(),p_customer_note)
  returning id into booking;
  return booking;
end $$;
revoke all on function public.create_booking_with_customer(uuid,text,text,text,text,date,date,time,time,integer,public.booking_source,public.booking_status,numeric,numeric,numeric) from public;
grant execute on function public.create_booking_with_customer(uuid,text,text,text,text,date,date,time,time,integer,public.booking_source,public.booking_status,numeric,numeric,numeric) to authenticated;

create or replace function public.update_booking_status(p_booking_id uuid,p_status public.booking_status)
returns void language plpgsql security definer set search_path=public
as $$
declare target_booking public.bookings%rowtype; current_status public.booking_status; role_now public.app_role;
begin
  role_now=public.current_app_role();
  if auth.uid() is null or role_now is null then raise insufficient_privilege using message='Not authorized.'; end if;
  select * into target_booking from public.bookings where id=p_booking_id and tenant_id=public.current_tenant_id() for update;
  current_status=target_booking.status;
  if not found then raise no_data_found using message='Booking not found.'; end if;
  if role_now='staff' then
    if target_booking.created_by<>auth.uid() and target_booking.assigned_to is distinct from auth.uid() then raise insufficient_privilege using message='Staff cannot update an unassigned booking.'; end if;
    if not ((current_status='confirmed' and p_status='checked_in') or (current_status='checked_in' and p_status='checked_out')) then
      raise insufficient_privilege using message='Staff can only check guests in or out.';
    end if;
  elsif role_now='manager' then
    if not ((current_status='pending' and p_status in ('confirmed','cancelled','no_show')) or (current_status='confirmed' and p_status in ('checked_in','cancelled','no_show')) or (current_status='checked_in' and p_status='checked_out') or p_status=current_status) then
      raise check_violation using message='Invalid booking status transition.';
    end if;
  elsif role_now not in ('owner','admin') then raise insufficient_privilege using message='Not authorized to update booking status.';
  end if;
  update public.bookings set status=p_status,updated_at=now() where id=p_booking_id;
end $$;
revoke all on function public.update_booking_status(uuid,public.booking_status) from public;
grant execute on function public.update_booking_status(uuid,public.booking_status) to authenticated;

create table public.payments (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id),
  booking_id uuid not null, amount numeric(14,0) not null check(amount>0), payment_type public.payment_type not null,
  payment_method public.payment_method not null, payment_date date not null, external_reference text, note text,
  collected_by uuid references public.profiles(id), created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(), voided_at timestamptz, voided_by uuid references public.profiles(id),
  foreign key(tenant_id,booking_id) references public.bookings(tenant_id,id)
);
create index payments_booking_idx on public.payments(booking_id,payment_date);

-- Record a receipt atomically so simultaneous collection requests cannot over-collect.
create or replace function public.record_booking_receipt(
  p_booking_id uuid,p_amount numeric,p_payment_method public.payment_method,p_payment_date date,p_note text default null
) returns uuid language plpgsql security definer set search_path=public
as $$
declare b public.bookings%rowtype; already_received numeric(14,0); new_payment_id uuid; role_now public.app_role;
begin
  role_now=public.current_app_role();
  if auth.uid() is null or role_now not in ('owner','admin','manager','staff','accountant') then
    raise insufficient_privilege using message='Not authorized to record a payment.';
  end if;
  if p_amount<=0 or p_amount<>trunc(p_amount) then raise check_violation using message='Payment amount must be a positive whole VND amount.'; end if;
  select * into b from public.bookings where id=p_booking_id and tenant_id=public.current_tenant_id() for update;
  if not found then raise no_data_found using message='Booking not found.'; end if;
  if role_now='staff' and b.created_by<>auth.uid() and b.assigned_to is distinct from auth.uid() then raise insufficient_privilege using message='Staff cannot collect for an unassigned booking.'; end if;
  select coalesce(sum(amount),0) into already_received from public.payments where booking_id=p_booking_id and payment_type='receipt' and voided_at is null;
  if already_received+p_amount>b.total_amount then raise check_violation using message='Receipt would exceed booking value.'; end if;
  insert into public.payments(tenant_id,booking_id,amount,payment_type,payment_method,payment_date,note,collected_by,created_by)
  values(b.tenant_id,b.id,p_amount,'receipt',p_payment_method,p_payment_date,p_note,auth.uid(),auth.uid()) returning id into new_payment_id;
  return new_payment_id;
end $$;
revoke all on function public.record_booking_receipt(uuid,numeric,public.payment_method,date,text) from public;
grant execute on function public.record_booking_receipt(uuid,numeric,public.payment_method,date,text) to authenticated;

create table public.expenses (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id),
  apartment_id uuid not null, expense_date date not null, category text not null, description text,
  amount numeric(14,0) not null check(amount>0), paid_by uuid references public.profiles(id), created_by uuid not null references public.profiles(id),
  status text not null default 'pending' check(status in ('pending','approved','rejected','paid')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  foreign key(tenant_id,apartment_id) references public.apartments(tenant_id,id)
);

create table public.maintenance_blocks (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id), apartment_id uuid not null,
  start_date date not null, end_date date not null, reason text not null, status text not null default 'active' check(status in ('active','cancelled')),
  created_by uuid not null references public.profiles(id), created_at timestamptz not null default now(),
  check(end_date>start_date), foreign key(tenant_id,apartment_id) references public.apartments(tenant_id,id)
);
create index maintenance_tenant_dates_idx on public.maintenance_blocks(tenant_id,apartment_id,start_date,end_date) where status='active';

-- A shared exclusion index arbitrates booking-vs-maintenance conflicts as well as booking-vs-booking,
-- including concurrent transactions that cannot see each other's uncommitted rows.
create table public.reservation_blocks (
  id bigint generated always as identity primary key, apartment_id uuid not null references public.apartments(id),
  source_type text not null check(source_type in ('booking','maintenance')), source_id uuid not null,
  stay daterange not null, unique(source_type,source_id),
  exclude using gist(apartment_id with =,stay with &&)
);
alter table public.reservation_blocks enable row level security;
revoke all on public.reservation_blocks from anon,authenticated;
create or replace function public.sync_booking_reservation_block() returns trigger
language plpgsql security definer set search_path=public
as $$
begin
  if TG_OP='UPDATE' then delete from public.reservation_blocks where source_type='booking' and source_id=old.id; end if;
  if new.status not in ('cancelled','no_show') then
    insert into public.reservation_blocks(apartment_id,source_type,source_id,stay)
    values(new.apartment_id,'booking',new.id,daterange(new.checkin_date,new.checkout_date,'[)'));
  end if;
  return new;
end $$;
create trigger booking_materialize_reservation after insert or update of apartment_id,checkin_date,checkout_date,status on public.bookings
for each row execute function public.sync_booking_reservation_block();
create or replace function public.sync_maintenance_reservation_block() returns trigger
language plpgsql security definer set search_path=public
as $$
begin
  if TG_OP='UPDATE' then delete from public.reservation_blocks where source_type='maintenance' and source_id=old.id; end if;
  if new.status='active' then
    insert into public.reservation_blocks(apartment_id,source_type,source_id,stay)
    values(new.apartment_id,'maintenance',new.id,daterange(new.start_date,new.end_date,'[)'));
  end if;
  return new;
end $$;
create trigger maintenance_materialize_reservation after insert or update of apartment_id,start_date,end_date,status on public.maintenance_blocks
for each row execute function public.sync_maintenance_reservation_block();

create table public.audit_logs (
  id bigint generated always as identity primary key, tenant_id uuid not null references public.tenants(id),
  user_id uuid references public.profiles(id), action text not null, entity_type text not null, entity_id uuid,
  old_data jsonb, new_data jsonb, created_at timestamptz not null default now()
);
create index audit_logs_tenant_entity_idx on public.audit_logs(tenant_id,entity_type,entity_id,created_at desc);

create or replace function public.current_tenant_id() returns uuid language sql stable security definer set search_path=public
as $$ select tenant_id from public.profiles where id=auth.uid() and status='active' $$;
create or replace function public.current_app_role() returns public.app_role language sql stable security definer set search_path=public
as $$ select role from public.profiles where id=auth.uid() and status='active' $$;
revoke all on function public.current_tenant_id() from public;
revoke all on function public.current_app_role() from public;
grant execute on function public.current_tenant_id() to authenticated;
grant execute on function public.current_app_role() to authenticated;

-- Serialize reservations per apartment, then validate against both bookings and maintenance.
-- [check-in, check-out) means a same-day turnover is allowed.
create or replace function public.check_reservation_conflict() returns trigger
language plpgsql security definer set search_path=public
as $$
begin
  if new.status not in ('cancelled','no_show') then
    perform pg_advisory_xact_lock(hashtextextended(new.apartment_id::text,0));
    if exists(select 1 from public.bookings b where b.apartment_id=new.apartment_id and b.id<>new.id
      and b.status not in ('cancelled','no_show') and daterange(b.checkin_date,b.checkout_date,'[)') && daterange(new.checkin_date,new.checkout_date,'[)')) then
      raise exclusion_violation using message='Apartment already has an overlapping booking.';
    end if;
    if exists(select 1 from public.maintenance_blocks m where m.apartment_id=new.apartment_id and m.status='active'
      and daterange(m.start_date,m.end_date,'[)') && daterange(new.checkin_date,new.checkout_date,'[)')) then
      raise exclusion_violation using message='Apartment is blocked for maintenance during these dates.';
    end if;
  end if;
  if new.guest_count>(select max_guests from public.apartments where id=new.apartment_id) then
    raise check_violation using message='Guest count exceeds apartment capacity.';
  end if;
  return new;
end $$;
create trigger bookings_prevent_conflicts before insert or update of apartment_id,checkin_date,checkout_date,status,guest_count on public.bookings
for each row execute function public.check_reservation_conflict();

create or replace function public.check_maintenance_conflict() returns trigger
language plpgsql security definer set search_path=public
as $$
begin
  if new.status='active' then
    perform pg_advisory_xact_lock(hashtextextended(new.apartment_id::text,0));
    if exists(select 1 from public.bookings b where b.apartment_id=new.apartment_id and b.status not in ('cancelled','no_show')
      and daterange(b.checkin_date,b.checkout_date,'[)') && daterange(new.start_date,new.end_date,'[)')) then
      raise exclusion_violation using message='Maintenance period overlaps an active booking.';
    end if;
  end if;
  return new;
end $$;
create trigger maintenance_prevent_conflicts before insert or update of apartment_id,start_date,end_date,status on public.maintenance_blocks
for each row execute function public.check_maintenance_conflict();

create or replace function public.write_audit_log() returns trigger language plpgsql security definer set search_path=public
as $$
declare before_row jsonb; after_row jsonb; row_id uuid; tenant uuid;
begin
  if TG_OP<>'INSERT' then before_row=to_jsonb(old); end if;
  if TG_OP<>'DELETE' then after_row=to_jsonb(new); end if;
  row_id=coalesce((after_row->>'id')::uuid,(before_row->>'id')::uuid);
  tenant=coalesce((after_row->>'tenant_id')::uuid,(before_row->>'tenant_id')::uuid);
  insert into public.audit_logs(tenant_id,user_id,action,entity_type,entity_id,old_data,new_data)
  values(tenant,auth.uid(),lower(TG_OP),TG_TABLE_NAME,row_id,before_row,after_row);
  if TG_OP='DELETE' then return old; else return new; end if;
end $$;
create trigger audit_apartments after insert or update or delete on public.apartments for each row execute function public.write_audit_log();
create trigger audit_customers after insert or update or delete on public.customers for each row execute function public.write_audit_log();
create trigger audit_bookings after insert or update or delete on public.bookings for each row execute function public.write_audit_log();
create trigger audit_payments after insert or update or delete on public.payments for each row execute function public.write_audit_log();
create trigger audit_expenses after insert or update or delete on public.expenses for each row execute function public.write_audit_log();

alter table public.tenants enable row level security;
alter table public.profiles enable row level security;
alter table public.apartments enable row level security;
alter table public.customers enable row level security;
alter table public.bookings enable row level security;
alter table public.payments enable row level security;
alter table public.expenses enable row level security;
alter table public.maintenance_blocks enable row level security;
alter table public.audit_logs enable row level security;

create policy tenant_read on public.tenants for select to authenticated using(id=public.current_tenant_id());
create policy profiles_read on public.profiles for select to authenticated using(tenant_id=public.current_tenant_id() and (id=auth.uid() or public.current_app_role() in ('owner','admin','manager')));
create policy profiles_admin_update on public.profiles for update to authenticated using(tenant_id=public.current_tenant_id() and public.current_app_role() in ('owner','admin')) with check(tenant_id=public.current_tenant_id());
create policy apartments_read on public.apartments for select to authenticated using(tenant_id=public.current_tenant_id());
create policy apartments_manage on public.apartments for all to authenticated using(tenant_id=public.current_tenant_id() and public.current_app_role() in ('owner','admin','manager')) with check(tenant_id=public.current_tenant_id() and public.current_app_role() in ('owner','admin','manager'));
create policy customers_read on public.customers for select to authenticated using(tenant_id=public.current_tenant_id() and (
  public.current_app_role() in ('owner','admin','manager','accountant') or
  (public.current_app_role()='staff' and (customers.created_by=auth.uid() or exists(select 1 from public.bookings b where b.customer_id=customers.id and b.tenant_id=customers.tenant_id and (b.created_by=auth.uid() or b.assigned_to=auth.uid()))))
));
create policy customers_insert on public.customers for insert to authenticated with check(tenant_id=public.current_tenant_id() and public.current_app_role() in ('owner','admin','manager','staff'));
create policy customers_update on public.customers for update to authenticated using(tenant_id=public.current_tenant_id() and public.current_app_role() in ('owner','admin','manager')) with check(tenant_id=public.current_tenant_id());
create policy bookings_read on public.bookings for select to authenticated using(tenant_id=public.current_tenant_id() and (
  public.current_app_role() in ('owner','admin','manager','accountant') or
  (public.current_app_role()='staff' and (created_by=auth.uid() or assigned_to=auth.uid()))
));
create policy bookings_insert on public.bookings for insert to authenticated with check(tenant_id=public.current_tenant_id() and public.current_app_role() in ('owner','admin','manager','staff'));
create policy bookings_update on public.bookings for update to authenticated using(tenant_id=public.current_tenant_id() and public.current_app_role() in ('owner','admin','manager')) with check(tenant_id=public.current_tenant_id());
create policy payments_read on public.payments for select to authenticated using(tenant_id=public.current_tenant_id() and public.current_app_role() in ('owner','admin','manager','accountant'));
create policy payments_staff_own on public.payments for select to authenticated using(tenant_id=public.current_tenant_id() and collected_by=auth.uid() and public.current_app_role()='staff');
create policy expenses_read on public.expenses for select to authenticated using(tenant_id=public.current_tenant_id() and public.current_app_role() in ('owner','admin','manager','accountant'));
create policy expenses_insert on public.expenses for insert to authenticated with check(tenant_id=public.current_tenant_id() and public.current_app_role() in ('owner','admin','manager','accountant'));
create policy maintenance_read on public.maintenance_blocks for select to authenticated using(tenant_id=public.current_tenant_id());
create policy maintenance_manage on public.maintenance_blocks for all to authenticated using(tenant_id=public.current_tenant_id() and public.current_app_role() in ('owner','admin','manager')) with check(tenant_id=public.current_tenant_id() and public.current_app_role() in ('owner','admin','manager'));
create policy audit_read on public.audit_logs for select to authenticated using(tenant_id=public.current_tenant_id() and public.current_app_role() in ('owner','admin','accountant'));

grant select on public.tenants,public.profiles,public.apartments,public.customers,public.bookings,public.payments,public.expenses,public.maintenance_blocks,public.audit_logs to authenticated;
grant insert,update on public.apartments to authenticated;
grant insert,update on public.customers to authenticated;
grant insert,update on public.bookings to authenticated;
revoke insert,update,delete on public.payments from authenticated;
grant insert,update on public.expenses,public.maintenance_blocks to authenticated;

-- Finance audit history is append-only for signed-in clients; corrections are recorded as new entries later.
revoke update,delete on public.payments from authenticated;
revoke update,delete on public.audit_logs from authenticated;
