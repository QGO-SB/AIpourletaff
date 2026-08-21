import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function GET() {
  const supabase = createClient();
  const { data: authData } = await supabase.auth.getUser();

  if (!authData.user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const orchestratorUrl = process.env.ORCHESTRATOR_URL;
  const orchestratorSecret = process.env.ORCHESTRATOR_SECRET;

  if (!orchestratorUrl || !orchestratorSecret) {
    return NextResponse.json(
      { error: "config", message: "ORCHESTRATOR_URL / ORCHESTRATOR_SECRET non configurés" },
      { status: 500 }
    );
  }

  let statusRes: Response;
  try {
    statusRes = await fetch(`${orchestratorUrl}/status`, {
      headers: { Authorization: `Bearer ${orchestratorSecret}` },
      cache: "no-store",
    });
  } catch {
    return NextResponse.json(
      { error: "unreachable", message: "Le serveur maison est injoignable." },
      { status: 502 }
    );
  }

  if (!statusRes.ok) {
    return NextResponse.json({ error: "status_failed" }, { status: 502 });
  }

  const body = await statusRes.json().catch(() => ({ slots: [], maxConcurrent: 0 }));
  const slots = Array.isArray(body.slots) ? body.slots : [];
  const used = slots.filter((s: { trigram: string | null }) => s.trigram).length;

  return NextResponse.json({ used, max: body.maxConcurrent ?? slots.length });
}
