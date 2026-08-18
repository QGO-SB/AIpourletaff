"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export default function DashboardPage() {
  const router = useRouter();
  const supabase = createClient();
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function openRemoteDesktop() {
    setLoading(true);
    setError(null);

    const res = await fetch("/api/vm-access");
    setLoading(false);

    if (!res.ok) {
      setError("Impossible de récupérer l'accès au bureau distant.");
      return;
    }

    const { url, user, pass } = await res.json();
    const urlWithCreds = url.replace(
      "https://",
      `https://${encodeURIComponent(user)}:${encodeURIComponent(pass)}@`
    );
    window.open(urlWithCreds, "_blank", "noopener,noreferrer");
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

      <button onClick={openRemoteDesktop} disabled={loading} style={{ padding: "10px 20px" }}>
        {loading ? "Ouverture..." : "Ouvrir mon bureau distant"}
      </button>

      {error && <p style={{ color: "crimson" }}>{error}</p>}

      <p style={{ fontSize: 13, color: "#666", maxWidth: 360, textAlign: "center" }}>
        Si le navigateur redemande les identifiants après ouverture, saisis
        ceux de ta VM (Basic Auth).
      </p>

      <button onClick={handleLogout} style={{ marginTop: 24, padding: "6px 14px" }}>
        Se déconnecter
      </button>
    </main>
  );
}
