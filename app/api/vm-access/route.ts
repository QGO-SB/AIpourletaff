import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function GET() {
  const supabase = createClient();
  const { data: authData } = await supabase.auth.getUser();

  if (!authData.user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("slot, domain, basic_user, basic_pass")
    .eq("id", authData.user.id)
    .single();

  if (profileError || !profile) {
    return NextResponse.json(
      { error: "no_profile", message: "Aucun bureau n'est assigné à ce compte." },
      { status: 404 }
    );
  }

  const orchestratorUrl = process.env.ORCHESTRATOR_URL;
  const orchestratorSecret = process.env.ORCHESTRATOR_SECRET;

  if (!orchestratorUrl || !orchestratorSecret) {
    return NextResponse.json(
      { error: "config", message: "ORCHESTRATOR_URL / ORCHESTRATOR_SECRET non configurés" },
      { status: 500 }
    );
  }

  let startRes: Response;
  try {
    startRes = await fetch(`${orchestratorUrl}/start/${profile.slot}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${orchestratorSecret}` },
    });
  } catch {
    return NextResponse.json(
      { error: "unreachable", message: "Le serveur maison est injoignable." },
      { status: 502 }
    );
  }

  if (startRes.status === 503) {
    const body = await startRes.json().catch(() => ({}));
    return NextResponse.json(
      {
        error: "capacity",
        message: body.message || "Tous les bureaux sont occupés, réessaie dans quelques minutes.",
      },
      { status: 503 }
    );
  }

  if (!startRes.ok) {
    return NextResponse.json(
      { error: "start_failed", message: "Impossible de démarrer le bureau distant." },
      { status: 502 }
    );
  }

  return NextResponse.json({
    url: `https://${profile.domain}`,
    user: profile.basic_user,
    pass: profile.basic_pass,
  });
}
