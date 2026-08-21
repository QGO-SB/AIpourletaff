"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

const TRIGRAM_STORAGE_KEY = "bureau-trigram";

const AI_OPTIONS = [
  { name: "Claude", url: "https://claude.ai" },
  { name: "ChatGPT", url: "https://chatgpt.com" },
  { name: "Perplexity", url: "https://www.perplexity.ai" },
  { name: "Gemini", url: "https://gemini.google.com" },
  { name: "Copilot", url: "https://copilot.microsoft.com" },
  { name: "Mistral", url: "https://chat.mistral.ai" },
  { name: "Qwen", url: "https://chat.qwen.ai" },
  { name: "DeepSeek", url: "https://chat.deepseek.com" },
  { name: "Grok", url: "https://grok.com" },
  { name: "Meta AI", url: "https://www.meta.ai" },
];

export default function DashboardPage() {
  const router = useRouter();
  const supabase = createClient();
  const [trigram, setTrigram] = useState("");
  const [customUrl, setCustomUrl] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState<string | null>(null);

  useEffect(() => {
    const saved = window.localStorage.getItem(TRIGRAM_STORAGE_KEY);
    if (saved) setTrigram(saved);
  }, []);

  async function openSite(name: string, rawUrl: string) {
    setError(null);

    const cleanedTrigram = trigram.trim();
    if (!/^[a-zA-Z0-9]{2,12}$/.test(cleanedTrigram)) {
      setError("Entre un trigramme valide (2 à 12 lettres/chiffres).");
      return;
    }

    let normalizedUrl = rawUrl.trim();
    if (!/^https?:\/\//i.test(normalizedUrl)) {
      normalizedUrl = `https://${normalizedUrl}`;
    }
    try {
      new URL(normalizedUrl);
    } catch {
      setError("URL invalide.");
      return;
    }

    setLoading(name);
    const res = await fetch("/portal/api/vm-access", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ trigram: cleanedTrigram, url: normalizedUrl }),
    });
    const body = await res.json().catch(() => ({}));
    setLoading(null);

    if (!res.ok) {
      setError(body.message || "Impossible de démarrer la session.");
      return;
    }

    window.localStorage.setItem(TRIGRAM_STORAGE_KEY, cleanedTrigram);
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
        gap: 20,
        padding: 24,
      }}
    >
      <h1>Choisis ton IA</h1>

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

      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fit, minmax(120px, 1fr))",
          gap: 10,
          width: "100%",
          maxWidth: 560,
        }}
      >
        {AI_OPTIONS.map((ai) => (
          <button
            key={ai.name}
            onClick={() => openSite(ai.name, ai.url)}
            disabled={loading !== null}
            style={{ padding: "14px 8px" }}
          >
            {loading === ai.name ? "Démarrage…" : ai.name}
          </button>
        ))}
      </div>

      <div
        style={{
          display: "flex",
          flexDirection: "column",
          gap: 8,
          alignItems: "center",
          width: "100%",
          maxWidth: 360,
        }}
      >
        <label htmlFor="customUrl" style={{ fontSize: 14 }}>
          Autre site (URL)
        </label>
        <input
          id="customUrl"
          value={customUrl}
          onChange={(e) => setCustomUrl(e.target.value)}
          placeholder="https://exemple.com"
          style={{ padding: 8, width: "100%" }}
        />
        <button
          onClick={() => openSite("Autre", customUrl)}
          disabled={loading !== null || !customUrl.trim()}
          style={{ padding: "10px 20px", width: "100%" }}
        >
          {loading === "Autre" ? "Démarrage…" : "Ouvrir ce site"}
        </button>
      </div>

      {error && <p style={{ color: "crimson", maxWidth: 360, textAlign: "center" }}>{error}</p>}

      <p style={{ fontSize: 13, color: "#666", maxWidth: 360, textAlign: "center" }}>
        Première connexion avec ce trigramme : ton profil se crée tout seul.
        Si tu changes de site, ta session redémarre dessus (tes comptes connectés restent).
      </p>

      <button onClick={handleLogout} style={{ marginTop: 8, padding: "6px 14px" }}>
        Se déconnecter
      </button>
    </main>
  );
}
