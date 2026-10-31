"use client";
import { useFormStatus } from "react-dom";
export function SubmitButton({children}:{children:React.ReactNode}){const {pending}=useFormStatus();return <button className="btn" disabled={pending}>{pending?"Đang lưu…":children}</button>}
