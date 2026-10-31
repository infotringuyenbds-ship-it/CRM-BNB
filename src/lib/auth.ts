import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function requireUser() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: profile, error } = await supabase.from("profiles").select("id, full_name, role, tenant_id, status").eq("id", user.id).single();
  if (error || !profile || profile.status !== "active") redirect("/login?error=profile");
  return { supabase, user, profile };
}
