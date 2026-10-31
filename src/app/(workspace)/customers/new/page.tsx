import Link from "next/link";
import { requireUser } from "@/lib/auth";
import { SideNav } from "@/components/side-nav";
import { CustomerForm } from "@/components/forms";
export default async function NewCustomer(){await requireUser();return <><SideNav active="/bookings"/><main className="main"><div className="heading"><div><h1>Thêm khách hàng</h1><div className="sub">Lưu hồ sơ khách cho lần đặt phòng tiếp theo</div></div><Link className="btn secondary" href="/customers">Quay lại</Link></div><section className="card" style={{maxWidth:780}}><CustomerForm/></section></main></>}
