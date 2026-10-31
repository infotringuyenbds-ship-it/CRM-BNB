import Link from "next/link";
import { notFound } from "next/navigation";
import { requireUser } from "@/lib/auth";
import { SideNav } from "@/components/side-nav";
import { EditApartmentForm } from "@/components/forms";
export default async function EditApartmentPage({params}:{params:Promise<{id:string}>}){const {id}=await params;const {supabase}=await requireUser();const {data}=await supabase.from("apartments").select("id,code,name,building,address,floor,type,bedrooms,max_guests,status").eq("id",id).maybeSingle();if(!data)notFound();return <><SideNav active="/apartments"/><main className="main"><div className="heading"><div><h1>Sửa căn hộ</h1><div className="sub">{data.code} · Cập nhật thông tin căn hộ</div></div><Link className="btn secondary" href="/apartments">Quay lại</Link></div><section className="card" style={{maxWidth:780}}><EditApartmentForm apartment={data}/></section></main></>}
