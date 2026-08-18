import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function GET() {
  const supabase = createClient();
  const { data } = await supabase.auth.getUser();

  if (!data.user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const url = process.env.VM_URL;
  const user = process.env.VM_BASIC_AUTH_USER;
  const pass = process.env.VM_BASIC_AUTH_PASS;

  if (!url || !user || !pass) {
    return NextResponse.json(
      { error: "VM_URL / VM_BASIC_AUTH_USER / VM_BASIC_AUTH_PASS non configurés" },
      { status: 500 }
    );
  }

  return NextResponse.json({ url, user, pass });
}
