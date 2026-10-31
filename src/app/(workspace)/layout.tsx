import { requireUser } from "@/lib/auth";
export default async function WorkspaceLayout({children}:{children:React.ReactNode}){await requireUser();return <div className="shell">{children}</div>}
