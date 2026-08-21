"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

const TRIGRAM_STORAGE_KEY = "bureau-trigram";

const AI_OPTIONS = [
  { name: "Claude", url: "https://claude.ai", color: "#7c6fff" },
  { name: "ChatGPT", url: "https://chatgpt.com", color: "#10b981" },
  { name: "Perplexity", url: "https://www.perplexity.ai", color: "#38bdf8" },
  { name: "Gemini", url: "https://gemini.google.com", color: "#f472b6" },
  { name: "Copilot", url: "https://copilot.microsoft.com", color: "#60a5fa" },
  { name: "Mistral", url: "https://chat.mistral.ai", color: "#fb923c" },
  { name: "Qwen", url: "https://chat.qwen.ai", color: "#a78bfa" },
  { name: "DeepSeek", url: "https://chat.deepseek.com", color: "#34d399" },
  { name: "Grok", url: "https://grok.com", color: "#f87171" },
  { name: "Meta AI", url: "https://www.meta.ai", color: "#818cf8" },
];

type Capacity = { used: number; max: number };

export default function DashboardPage() {
  const router = useRouter();
  const supabase = createClient();
  const [trigram, setTrigram] = useState("");
  const [customUrl, setCustomUrl] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState<string | null>(null);
  const [capacity, setCapacity] = useState<Capacity | null>(null);

  useEffect(() => {
    const saved = window.localStorage.getItem(TRIGRAM_STORAGE_KEY);
    if (saved) setTrigram(saved);
  }, []);

  async function refreshCapacity() {
    const res = await fetch("/portal/api/vm-status");
    const body = await res.json().catch(() => ({}));
    if (res.ok && typeof body.used === "number" && typeof body.max === "number") {
      setCapacity({ used: body.used, max: body.max });
    }
  }

  useEffect(() => {
    refreshCapacity();
    const interval = setInterval(refreshCapacity, 15000);
    return () => clearInterval(interval);
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
    refreshCapacity();
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
        padding: "48px 24px",
        gap: 28,
      }}
    >
      <div style={{ textAlign: "center" }}>
        <h1 style={{ fontSize: 26, fontWeight: 700 }}>Choisis ton IA</h1>
        <p style={{ fontSize: 13, color: "var(--text-muted)", marginTop: 6 }}>
          Ton trigramme retrouve toujours ton profil, quel que soit le site.
        </p>
        {capacity && (
          <p
            style={{
              fontSize: 12,
              marginTop: 10,
              display: "inline-block",
              padding: "4px 12px",
              borderRadius: 999,
              border: "1px solid var(--border)",
              color: capacity.used >= capacity.max ? "var(--danger)" : "var(--text-muted)",
            }}
          >
            {capacity.used} / {capacity.max} sessions actives
            {capacity.used >= capacity.max ? " — complet, réessaie dans quelques minutes" : ""}
          </p>
        )}
      </div>

      <div
        className="card"
        style={{
          display: "flex",
          flexDirection: "column",
          gap: 8,
          alignItems: "center",
          padding: "18px 24px",
        }}
      >
        <label htmlFor="trigram" style={{ fontSize: 13, color: "var(--text-muted)" }}>
          Ton trigramme
        </label>
        <input
          id="trigram"
          value={trigram}
          onChange={(e) => setTrigram(e.target.value)}
          maxLength={12}
          placeholder="QGO"
          style={{ padding: "10px 12px", textAlign: "center", textTransform: "uppercase", width: 160, fontSize: 16, letterSpacing: 2 }}
        />
      </div>

      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fit, minmax(150px, 1fr))",
          gap: 12,
          width: "100%",
          maxWidth: 620,
        }}
      >
        {AI_OPTIONS.map((ai) => (
          <button
            key={ai.name}
            onClick={() => openSite(ai.name, ai.url)}
            disabled={loading !== null}
            className="card ai-btn"
          >
            <span className="ai-dot" style={{ background: ai.color }} />
            {loading === ai.name ? "Démarrage…" : ai.name}
          </button>
        ))}
      </div>

      <div
        className="card"
        style={{
          display: "flex",
          flexDirection: "column",
          gap: 10,
          width: "100%",
          maxWidth: 380,
          padding: "20px 24px",
        }}
      >
        <label htmlFor="customUrl" style={{ fontSize: 13, color: "var(--text-muted)" }}>
          Autre site (URL)
        </label>
        <input
          id="customUrl"
          value={customUrl}
          onChange={(e) => setCustomUrl(e.target.value)}
          placeholder="https://exemple.com"
          style={{ padding: "10px 12px", width: "100%" }}
        />
        <button
          onClick={() => openSite("Autre", customUrl)}
          disabled={loading !== null || !customUrl.trim()}
          className="btn-primary"
          style={{ padding: 12, width: "100%" }}
        >
          {loading === "Autre" ? "Démarrage…" : "Ouvrir ce site"}
        </button>
      </div>

      {error && <p className="error-banner" style={{ maxWidth: 380, textAlign: "center" }}>{error}</p>}

      <button onClick={handleLogout} className="btn-ghost" style={{ padding: "8px 16px", fontSize: 13 }}>
        Se déconnecter
      </button>
    </main>
  );
}
