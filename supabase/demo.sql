-- Explicitly requested demo data. Run only for the owner's tenant.
begin;
do $$
declare t uuid; u uuid := '51bba721-3af3-42ac-a619-828dcc392486'; a uuid; c uuid; b uuid; i int; j int; bedrooms int; rate numeric; d date := timezone('Asia/Ho_Chi_Minh',now())::date; s date; e date; st public.booking_status;
begin
select tenant_id into strict t from public.profiles where id=u;
for i in 1..10 loop
 a := md5(t::text||'demo-apartment-'||i)::uuid;
 bedrooms := case when i<=3 then 0 when i<=6 then 1 when i<=8 then 2 else 3 end;
 rate := case bedrooms when 0 then 650000 when 1 then 950000 when 2 then 1450000 else 2100000 end;
 insert into public.apartments(id,tenant_id,code,name,building,address,floor,type,bedrooms,max_guests,monthly_rent,management_fee,notes)
 values(a,t,'DEMO-'||lpad(i::text,2,'0'),'[DEMO] '||case when bedrooms=0 then 'Studio' else bedrooms||' phòng ngủ' end||' · Căn '||i,case when i<=5 then 'Riverside Residence' else 'City Garden' end,'Địa chỉ minh họa, TP. Hồ Chí Minh',5+i,case when bedrooms=0 then 'Studio' else bedrooms||' phòng ngủ' end,bedrooms,greatest(2,bedrooms*2),rate*12,750000,'DỮ LIỆU DEMO · Không phải căn hộ/giao dịch thật') on conflict(id) do nothing;
 for j in 1..5 loop
  c:=md5(t::text||'demo-customer-'||i||'-'||j)::uuid; b:=md5(t::text||'demo-booking-'||i||'-'||j)::uuid;
  insert into public.customers(id,tenant_id,name,phone,notes,created_by) values(c,t,'Khách DEMO '||i||'.'||j,'DEMO-'||i||'-'||j,'Hồ sơ giả lập, không phải khách thật',u) on conflict(id) do nothing;
  s:=case j when 1 then d-27 when 2 then d-18 when 3 then d-10 when 4 then case when i<=5 then d-2 else d end else d+5 end;
  e:=s+case when j=1 then 4 when j=2 then 5 when j=3 then 3 when j=4 then 3 else 4 end;
  st:=case when j<=3 then 'checked_out'::public.booking_status when j=4 and i<=5 then 'checked_in'::public.booking_status when j=5 and i%3=0 then 'pending'::public.booking_status else 'confirmed'::public.booking_status end;
  insert into public.bookings(id,tenant_id,apartment_id,customer_id,checkin_date,checkout_date,checkin_time,checkout_time,guest_count,source,status,room_amount,surcharge_amount,discount_amount,platform_fee,total_amount,created_by,customer_note)
  values(b,t,a,c,s,e,'14:00','12:00',greatest(2,bedrooms*2),case when i%3=0 then 'airbnb'::public.booking_source when i%3=1 then 'booking_com'::public.booking_source else 'direct'::public.booking_source end,st,rate*(e-s),100000,case when j=2 then 150000 else 0 end,case when i%3<>2 then rate*(e-s)*0.12 else 0 end,rate*(e-s)+100000-case when j=2 then 150000 else 0 end,u,'DỮ LIỆU DEMO · Giá phòng giả định, không phải giao dịch thật') on conflict(id) do nothing;
  if j<=4 then
   insert into public.payments(id,tenant_id,booking_id,amount,payment_type,payment_method,payment_date,collected_by,created_by,note)
   values(md5(b::text||'demo-receipt')::uuid,t,b,(rate*(e-s)+100000-case when j=2 then 150000 else 0 end)*case when j=4 then 0.5 else 1 end,'receipt','bank_transfer',s,u,u,'DỮ LIỆU DEMO · Khoản thu minh họa') on conflict(id) do nothing;
  end if;
 end loop;
 for j in 1..6 loop
  insert into public.expenses(id,tenant_id,apartment_id,expense_date,category,description,amount,paid_by,created_by,status)
  values(md5(a::text||'demo-expense-'||j)::uuid,t,a,date_trunc('month',d)::date+(j-1),case j when 1 then 'Tiền thuê căn hộ' when 2 then 'Điện nước' when 3 then 'Internet' when 4 then 'Vệ sinh' when 5 then 'Phí quản lý' else 'Đồ tiêu hao' end,'DỮ LIỆU DEMO · Chi phí giả định',case j when 1 then rate*12 when 2 then 850000+bedrooms*250000 when 3 then 250000 when 4 then 600000 when 5 then 750000 else 350000 end,u,u,'paid') on conflict(id) do nothing;
 end loop;
end loop;
end $$;
create or replace view public.booking_revenue_nights with (security_invoker=true) as
select b.tenant_id,b.id as booking_id,b.apartment_id,n::date as stay_date,
floor((b.total_amount-b.platform_fee)/(b.checkout_date-b.checkin_date)) + case when n::date=b.checkout_date-1 then mod(b.total_amount-b.platform_fee,b.checkout_date-b.checkin_date) else 0 end as recognized_amount
from public.bookings b cross join lateral generate_series(b.checkin_date::timestamp,(b.checkout_date-1)::timestamp,interval '1 day') n
where b.status in ('confirmed','checked_in','checked_out') and n::date < timezone('Asia/Ho_Chi_Minh',now())::date;
grant select on public.booking_revenue_nights to authenticated;
commit;
