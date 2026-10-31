import { notFound } from "next/navigation";
import { SideNav } from "@/components/side-nav";
import { requireUser } from "@/lib/auth";
const areas:Record<string,{title:string;phase:string;description:string}>= {
  operations:{title:"Vận hành",phase:"Giai đoạn 2",description:"Quy trình nhận/trả phòng, công việc vệ sinh, bảo trì và phân công nhân viên sẽ được triển khai ở giai đoạn Operations."},
  finance:{title:"Thu chi",phase:"Giai đoạn 3",description:"Ghi nhận thanh toán, hoàn tiền, chi phí, đối soát và báo cáo lợi nhuận sẽ được triển khai ở giai đoạn Finance."},
  shareholders:{title:"Cổ đông",phase:"Giai đoạn 4",description:"Quản lý cổ đông, tỷ lệ sở hữu, kỳ phân chia lợi nhuận và lịch sử chi trả sẽ được triển khai ở giai đoạn Shareholders."},
  reports:{title:"Báo cáo",phase:"Giai đoạn 5",description:"Báo cáo doanh thu, lợi nhuận, công suất phòng, chốt sổ tháng và xuất tệp sẽ được triển khai ở giai đoạn Reports."},
  notifications:{title:"Thông báo",phase:"Giai đoạn 2",description:"Thông báo vận hành theo lịch chạy máy chủ sẽ được triển khai cùng quy trình Operations."},
  settings:{title:"Cài đặt",phase:"Giai đoạn tiếp theo",description:"Quản lý thành viên, phân quyền chi tiết và cấu hình hệ thống sẽ được triển khai sau nền tảng Phase 1."}
};
export default async function PlannedArea({params}:{params:Promise<{module:string}>}){await requireUser();const {module}=await params;const area=areas[module];if(!area)notFound();return <><SideNav active={`/${module}`}/><main className="main"><div className="heading"><div><h1>{area.title}</h1><div className="sub">BNB Manager · Lộ trình phát triển</div></div></div><section className="card" style={{maxWidth:760,padding:28}}><span className="pill blue">{area.phase}</span><h2 style={{fontSize:18,color:"var(--navy)",margin:"16px 0 8px"}}>Chưa triển khai</h2><p className="sub" style={{fontSize:13,lineHeight:1.7,margin:0}}>{area.description}</p></section></main></>}
