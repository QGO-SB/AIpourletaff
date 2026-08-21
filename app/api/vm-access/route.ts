import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

const TRIGRAM_RE = /^[a-zA-Z0-9]{2,12}$/;

export async function POST(request: Request) {
  const supabase = createClient();
  const { data: authData } = await supabase.auth.getUser();

  if (!authData.user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const body = await request.json().catch(() => ({}));
  const trigram = typeof body.trigram === "string" ? body.trigram.trim() : "";
  const rawUrl = typeof body.url === "string" ? body.url.trim() : "";

  if (!TRIGRAM_RE.test(trigram)) {
    return NextResponse.json(
      { error: "invalid_trigram", message: "Trigramme invalide (2 à 12 lettres/chiffres)." },
      { status: 400 }
    );
  }

  let targetUrl: string;
  try {
    const parsed = new URL(rawUrl);
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") throw new Error("bad_protocol");
    targetUrl = parsed.toString();
  } catch {
    return NextResponse.json(
      { error: "invalid_url", message: "URL invalide (doit commencer par http:// ou https://)." },
      { status: 400 }
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

  let assignRes: Response;
  try {
    assignRes = await fetch(
      `${orchestratorUrl}/assign/${encodeURIComponent(trigram.toLowerCase())}?url=${encodeURIComponent(targetUrl)}`,
      {
        method: "POST",
        headers: { Authorization: `Bearer ${orchestratorSecret}` },
      }
    );
  } catch {
    return NextResponse.json(
      { error: "unreachable", message: "Le serveur maison est injoignable." },
      { status: 502 }
    );
  }

  const assignBody = await assignRes.json().catch(() => ({}));

  if (assignRes.status === 503) {
    return NextResponse.json(
      {
        error: "capacity",
        message: assignBody.message || "Tous les bureaux sont occupés, réessaie dans quelques minutes.",
      },
      { status: 503 }
    );
  }

  if (!assignRes.ok) {
    return NextResponse.json(
      { error: "start_failed", message: "Impossible de démarrer le bureau distant." },
      { status: 502 }
    );
  }

  return NextResponse.json({
    url: `https://${assignBody.domain}`,
  });
}
