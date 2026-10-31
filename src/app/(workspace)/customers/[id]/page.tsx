import Link from "next/link";
import { notFound } from "next/navigation";
import { requireUser } from "@/lib/auth";
import { SideNav } from "@/components/side-nav";
import { CustomerForm } from "@/components/forms";
export default async function EditCustomer({params}:{params:Promise<{id:string}>}){const {id}=await params;const {supabase}=await requireUser();const {data}=await supabase.from("customers").select("id,name,phone,email,notes").eq("id",id).maybeSingle();if(!data)notFound();return <><SideNav active="/bookings"/><main className="main"><div className="heading"><div><h1>Hồ sơ khách hàng</h1><div className="sub">Cập nhật thông tin liên hệ và ghi chú</div></div><Link className="btn secondary" href="/customers">Quay lại</Link></div><section className="card" style={{maxWidth:780}}><CustomerForm customer={data}/></section></main></>}
