# BNB Manager — Phase 1

Ứng dụng quản lý căn hộ cho thuê ngắn ngày, xây dựng bằng Next.js, TypeScript, Supabase Auth và PostgreSQL. Giao diện tiếng Việt, múi giờ hiển thị Asia/Ho_Chi_Minh, tiền tệ VND.

## Phase 1 đã có

- Đăng nhập bằng Supabase Auth và kiểm tra hồ sơ người dùng ở máy chủ.
- Dashboard từ dữ liệu Supabase: căn hộ, booking đang ở, lịch nhận/trả hôm nay, booking sắp tới và chi phí đã nhập.
- Tạo/sửa căn hộ; danh sách căn hộ. Ngừng khai thác căn bằng trạng thái thay vì xóa dữ liệu.
- Tạo/cập nhật hồ sơ khách hàng; khách đặt lần đầu cũng được tạo tự động trong cùng giao dịch tạo booking.
- Tạo/xem booking, xem hồ sơ chi tiết và cập nhật trạng thái theo quyền; lịch theo tháng/căn hộ.
- Chặn booking trùng ngày bằng PostgreSQL exclusion constraints và một chỉ mục ràng buộc chung booking/bảo trì; booking đã hủy/khách không đến không chiếm lịch; cho phép ngày trả và ngày nhận cùng ngày.
- Chặn booking vướng kỳ bảo trì ở tầng dữ liệu.
- Tenant ID, vai trò cơ bản và RLS trên các bảng cốt lõi.
- Audit log cho căn hộ, khách, booking, thanh toán, chi phí; tiền lưu bằng NUMERIC.
- RPC nền tảng thu tiền khóa booking trước khi kiểm tra số đã thu, tránh ghi nhận vượt tổng giá trị do hai yêu cầu đồng thời. Giao diện thu tiền được lên kế hoạch ở giai đoạn Finance.

## Chưa có trong Phase 1

Chỉnh sửa ngày/giá booking, ghi nhận và hoàn tiền qua giao diện, bảo trì theo khoảng ngày qua giao diện, vệ sinh, notifications, phân quyền cổ đông, doanh thu ghi nhận theo đêm, báo cáo lợi nhuận, chốt sổ và export. Trạng thái booking và hồ sơ chi tiết đã có; các mục Phase sau hiện được đánh dấu rõ là chưa triển khai.

## Yêu cầu môi trường

- Node.js 20.9 trở lên và npm.
- Supabase project (PostgreSQL + Auth).
- Git/ Supabase CLI là tùy chọn để quản lý migration.

## Khởi chạy cục bộ

1. Tạo project Supabase và lấy Project URL, anon/publishable key.
2. Sao chép `.env.example` thành `.env.local`, điền hai biến công khai từ Supabase. Không đưa service role key vào trình duyệt hoặc `.env` của ứng dụng này.
3. Chạy migration `supabase/migrations/202610300001_core_foundation.sql` bằng Supabase SQL Editor hoặc Supabase CLI.
4. Tạo người dùng trong Supabase Dashboard → Authentication → Users (tắt public sign-up nếu đây là hệ thống nội bộ).
5. Tạo tenant và gán hồ sơ ban đầu bằng SQL Editor. Thay các giá trị ví dụ bằng ID/email của bạn:

```sql
insert into public.tenants(name) values ('BNB Manager') returning id;
-- Dùng UUID vừa nhận cùng UUID người dùng trong Authentication → Users:
insert into public.profiles(id, tenant_id, full_name, email, role)
values ('<auth-user-uuid>', '<tenant-uuid>', 'Chủ hệ thống', 'owner@example.com', 'owner');
```

6. Cài phụ thuộc và chạy ứng dụng:

```bash
npm install
npm run dev
```

Mở `http://localhost:3000`. Không có tài khoản demo hoặc seed mặc định; dữ liệu thật bắt đầu ở cơ sở dữ liệu tenant của bạn.

## Migrations

Phase 1 migration: `supabase/migrations/202610300001_core_foundation.sql`.

Migration tạo vai trò, tenants, profiles, apartments, customers, bookings, payments, expenses, maintenance blocks, audit logs, indexes, foreign keys, triggers chống xung đột và RLS policies. Mọi bảng dữ liệu vận hành đều gắn tenant. Không cấp quyền truy cập `service_role` cho ứng dụng web.

## Kiểm tra

```bash
npm run lint
npm run typecheck
npm run build
```

Kiểm tra booking chồng ngày bằng hai phiên đăng nhập cùng tạo reservation cho cùng căn hộ. Migration khóa theo apartment trong transaction và xác nhận lại booking cùng maintenance blocks trước khi ghi. Cùng ngày check-out/check-in được cho phép vì khoảng lưu trú là `[check-in, check-out)`.

## Deploy

Deploy Next.js lên Vercel; cấu hình `NEXT_PUBLIC_SUPABASE_URL` và `NEXT_PUBLIC_SUPABASE_ANON_KEY` ở project settings, chạy migration trên Supabase production trước khi mở ứng dụng. Bật HTTPS và tắt public sign-up nếu chỉ nhân viên được quản lý tài khoản. Cần bổ sung quy trình backup/restore của Supabase theo chính sách vận hành trước khi đưa dữ liệu sản xuất vào.

## Giới hạn hiện tại

- Chưa có seed giả; không dùng sample data để giả lập kết nối.
- Không có credentials trong workspace nên ứng dụng cần Supabase project và hồ sơ profile hợp lệ mới đăng nhập/đọc dữ liệu được.
- Môi trường thực thi hiện tại không có Node.js/npm; lint, typecheck và build chưa thể chạy tại đây.
- Dashboard Phase 1 chưa thay thế báo cáo doanh thu được ghi nhận theo đêm. Không dùng các chỉ số hiện tại làm báo cáo tài chính hoặc kỳ chốt sổ.
