import Link from "next/link";
import { createApartment } from "@/app/actions";
import { requireUser } from "@/lib/auth";
import { SideNav } from "@/components/side-nav";
import { SubmitButton } from "@/components/submit-button";
import { ApartmentForm } from "@/components/forms";
export default async function NewApartment(){await requireUser();return <><SideNav active="/apartments"/><main className="main"><div className="heading"><div><h1>Thêm căn hộ</h1><div className="sub">Thông tin cơ bản để đưa căn hộ vào quản lý</div></div><Link className="btn secondary" href="/apartments">Quay lại</Link></div><section className="card" style={{maxWidth:780}}><ApartmentForm action={createApartment}/></section></main></>}
