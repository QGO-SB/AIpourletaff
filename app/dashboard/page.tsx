"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

const TRIGRAM_STORAGE_KEY = "bureau-trigram";

export default function DashboardPage() {
  const router = useRouter();
  const supabase = createClient();
  const [trigram, setTrigram] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    const saved = window.localStorage.getItem(TRIGRAM_STORAGE_KEY);
    if (saved) setTrigram(saved);
  }, []);

  async function openRemoteDesktop() {
    setError(null);

    const cleaned = trigram.trim();
    if (!/^[a-zA-Z0-9]{2,12}$/.test(cleaned)) {
      setError("Entre un trigramme valide (2 à 12 lettres/chiffres).");
      return;
    }

    setLoading(true);
    const res = await fetch("/portal/api/vm-access", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ trigram: cleaned }),
    });
    const body = await res.json().catch(() => ({}));
    setLoading(false);

    if (!res.ok) {
      setError(body.message || "Impossible de récupérer l'accès au bureau distant.");
      return;
    }

    window.localStorage.setItem(TRIGRAM_STORAGE_KEY, cleaned);
    window.open(body.url, "_blank", "noopener,noreferrer");
  }

  async function handleLogout() {
    await supabase.auth.signOut();
    router.push("/login");
    router.refresh();
  }

  return (
    <main
      style={{
        display: "flex",
        minHeight: "100vh",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        gap: 16,
      }}
    >
      <h1>Mon bureau distant</h1>

      <div style={{ display: "flex", flexDirection: "column", gap: 8, alignItems: "center" }}>
        <label htmlFor="trigram" style={{ fontSize: 14 }}>
          Ton trigramme (ex. QGO)
        </label>
        <input
          id="trigram"
          value={trigram}
          onChange={(e) => setTrigram(e.target.value)}
          maxLength={12}
          style={{ padding: 8, textAlign: "center", textTransform: "uppercase", width: 160 }}
        />
      </div>

      <button onClick={openRemoteDesktop} disabled={loading} style={{ padding: "10px 20px" }}>
        {loading ? "Démarrage du bureau en cours…" : "Ouvrir mon bureau distant"}
      </button>

      {error && <p style={{ color: "crimson", maxWidth: 360, textAlign: "center" }}>{error}</p>}

      <p style={{ fontSize: 13, color: "#666", maxWidth: 360, textAlign: "center" }}>
        Première connexion avec ce trigramme : ton bureau se crée tout seul.
        Les fois suivantes, tu retrouves tes onglets et comptes connectés.
      </p>

      <button onClick={handleLogout} style={{ marginTop: 24, padding: "6px 14px" }}>
        Se déconnecter
      </button>
    </main>
  );
}
