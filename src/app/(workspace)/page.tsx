import Link from "next/link";
import { Building2,BedDouble,DoorOpen,SprayCan,CalendarCheck,CalendarClock,Wallet,CircleDollarSign,ArrowRight,Plus } from "lucide-react";
import { requireUser } from "@/lib/auth";
import { money,date } from "@/lib/format";
import { SideNav } from "@/components/side-nav";
import { FinanceOverview } from "@/components/finance-overview";

const icons=[Building2,BedDouble,DoorOpen,SprayCan,CalendarCheck,CalendarClock,Wallet,CircleDollarSign];
export default async function Dashboard(){
 const {supabase,profile}=await requireUser();const today=new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Ho_Chi_Minh"}).format(new Date());const todayUtc=new Date(`${today}T00:00:00Z`);const monthStart=`${today.slice(0,7)}-01`;const monthEndDate=new Date(Date.UTC(todayUtc.getUTCFullYear(),todayUtc.getUTCMonth()+1,1));const monthEnd=monthEndDate.toISOString().slice(0,10);
 const [apartments,occupied,arrivals,departures,upcoming,expenses]=await Promise.all([
  supabase.from("apartments").select("id,status",{count:"exact"}),
  supabase.from("bookings").select("id,apartment_id",{count:"exact"}).lte("checkin_date",today).gt("checkout_date",today).in("status",["pending","confirmed","checked_in"]),
  supabase.from("bookings").select("id,apartment:apartments(code),customer:customers(name),checkin_time").eq("checkin_date",today).in("status",["confirmed","pending"]).order("checkin_time"),
  supabase.from("bookings").select("id,apartment:apartments(code),customer:customers(name),checkout_time").eq("checkout_date",today).eq("status","checked_in").order("checkout_time"),
  supabase.from("bookings").select("id,status,total_amount,checkin_date,checkout_date,apartment:apartments(code),customer:customers(name)").gte("checkout_date",today).not("status","in","(cancelled,no_show)").order("checkin_date").limit(6),
  supabase.from("expenses").select("amount").gte("expense_date",monthStart).lt("expense_date",monthEnd)
 ]);
 const apt=apartments.data||[];const upcomingItems=upcoming.data||[];const occupiedIds=new Set((occupied.data||[]).map(b=>b.apartment_id));const vacantEstimate=apt.filter(a=>a.status==="active"&&!occupiedIds.has(a.id)).length;const cost=expenses.error?null:(expenses.data||[]).reduce((n,e)=>n+Number(e.amount||0),0);
 const {data:revenueNights}=await supabase.from('booking_revenue_nights').select('recognized_amount').gte('stay_date',monthStart).lt('stay_date',monthEnd);const monthRevenue=revenueNights?.reduce((s,v)=>s+Number(v.recognized_amount),0);
 const kpis=[
  {label:"Tổng căn hộ",value:apartments.count??"—",note:"Căn hộ trong hệ thống"},
  {label:"Đang có khách",value:occupied.count??"—",note:"Có booking lưu trú hôm nay"},
  {label:"Trống (ước tính)",value:vacantEstimate,note:"Chưa xét trạng thái vệ sinh"},
  {label:"Cần vệ sinh",value:"—",note:"Theo dõi ở giai đoạn Operations"},
  {label:"Check-in hôm nay",value:arrivals.data?.length??"—",note:"Booking đã xác nhận hoặc chờ"},
  {label:"Check-out hôm nay",value:departures.data?.length??"—",note:"Khách đang lưu trú"},
  {label:"Doanh thu thuần tháng",value:monthRevenue==null?'—':money(monthRevenue),note:"Theo đêm đã lưu trú, trừ phí nền tảng"},
  {label:"Chi phí tháng",value:cost===null?"—":money(cost),note:expenses.error?"Không có quyền xem chi phí":"Theo ngày ghi nhận chi phí"}
 ];
 return <><SideNav active="/"/><main className="main"><div className="heading"><div><h1>Tổng quan</h1><div className="sub">Tình hình vận hành ngày {date(today)} · {profile.full_name}</div></div><Link href="/bookings/new" className="btn"><Plus size={15}/>Tạo booking</Link></div><div className="kpis">{kpis.map((x,i)=>{const Icon=icons[i];return <section className="card kpi" key={x.label}><div className="kpi-head"><span>{x.label}</span><span className="kpi-icon"><Icon size={16}/></span></div><div className="kpi-value" style={i===6||i===7?{fontSize:19}:undefined}>{x.value}</div><div className="kpi-note">{x.note}</div></section>})}</div><div className="grid2"><section className="card"><div className="section-head"><div className="card-title">Lịch vận hành hôm nay</div><Link className="sub" href="/calendar">Mở lịch <ArrowRight size={12} style={{verticalAlign:"middle"}}/></Link></div>{(arrivals.data?.length||departures.data?.length)?<div className="table-wrap"><table className="table"><thead><tr><th>Khung giờ</th><th>Hoạt động</th><th>Căn hộ</th><th>Khách</th></tr></thead><tbody>{[...(arrivals.data||[]).map(x=>({...x,kind:"Check-in",time:x.checkin_time})),...(departures.data||[]).map(x=>({...x,kind:"Check-out",time:x.checkout_time}))].sort((a,b)=>(a.time||"").localeCompare(b.time||"")).map((x,i)=><tr key={i}><td>{x.time?.slice(0,5)||"—"}</td><td><span className={`pill ${x.kind==="Check-in"?"blue":"yellow"}`}>{x.kind}</span></td><td className="strong">{(x.apartment as {code?:string}|null)?.code||"—"}</td><td>{(x.customer as {name?:string}|null)?.name||"—"}</td></tr>)}</tbody></table></div>:<div className="empty">Hôm nay chưa có lịch nhận hoặc trả phòng.</div>}</section><section className="card"><div className="section-head"><div className="card-title">Booking sắp tới</div><Link className="sub" href="/bookings">Tất cả <ArrowRight size={12} style={{verticalAlign:"middle"}}/></Link></div>{upcomingItems.length?<div className="table-wrap"><table className="table"><thead><tr><th>Căn hộ / khách</th><th>Lưu trú</th><th>Trạng thái</th></tr></thead><tbody>{upcomingItems.slice(0,5).map(b=><tr key={b.id}><td><div className="strong">{(b.apartment as {code?:string}|null)?.code||"—"}</div><div className="sub" style={{marginTop:4}}>{(b.customer as {name?:string}|null)?.name||"Khách hàng"}</div></td><td>{date(b.checkin_date)} – {date(b.checkout_date)}</td><td><span className={`pill ${b.status==="checked_in"?"green":b.status==="pending"?"yellow":"blue"}`}>{({pending:"Chờ xác nhận",confirmed:"Đã xác nhận",checked_in:"Đang lưu trú",checked_out:"Đã trả phòng"} as Record<string,string>)[b.status]||b.status}</span></td></tr>)}</tbody></table></div>:<div className="empty">Chưa có booking nào. <Link href="/bookings/new" style={{color:"var(--teal)"}}>Tạo booking đầu tiên</Link></div>}</section></div><div className="notice" style={{marginTop:16}}>Doanh thu được ghi nhận theo đêm lưu trú và đối soát chi phí sẽ được triển khai trong giai đoạn Finance. Chưa dùng dashboard này để chốt số liệu tài chính.</div><FinanceOverview/></main></>;
}

