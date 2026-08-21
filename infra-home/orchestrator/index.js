// Orchestrateur : assigne à chaque "trigramme" (identifiant libre choisi par
// la personne, ex. "QGO") un conteneur Docker éphémère sur un slot libre,
// avec le volume persistant de ce trigramme monté dedans — donc peu importe
// le slot physique attribué, c'est toujours le profil Firefox de cette
// personne qui se charge. Le volume est créé automatiquement par Docker au
// premier usage : pas besoin d'enregistrer les trigrammes à l'avance.
//
// Aucune dépendance npm : parle directement à l'API Docker via le socket
// Unix /var/run/docker.sock.

const http = require("http");
const net = require("net");
const fs = require("fs");
const { execSync } = require("child_process");

const SLOT_COUNT = parseInt(process.env.SLOT_COUNT || "10", 10);
const BASE_PORT = parseInt(process.env.BASE_PORT || "3000", 10);
const IMAGE = process.env.WEBTOP_IMAGE || "webtop-firefox:local";
const MAX_CONCURRENT = parseInt(process.env.MAX_CONCURRENT || "5", 10);
const IDLE_MINUTES = parseInt(process.env.IDLE_MINUTES || "15", 10);
const SECRET = process.env.ORCH_SECRET;
const PORT = parseInt(process.env.ORCH_PORT || "8080", 10);
const DUCKDNS_PREFIX = process.env.DUCKDNS_PREFIX || "";
// Domaine Cloudflare Tunnel (dual-stack IPv4+IPv6, couvre aussi les clients
// sans IPv6). Prioritaire sur DuckDNS/IPv6 quand défini.
const PUBLIC_DOMAIN = process.env.PUBLIC_DOMAIN || "";
// Suivi persistant (survit aux redémarrages) de la dernière activité par
// trigramme, utilisé par cleanup.js pour purger les profils abandonnés.
const LAST_ACTIVE_FILE = process.env.LAST_ACTIVE_FILE || "/var/lib/orchestrator/last-active.json";

if (!SECRET) {
  console.error("ORCH_SECRET manquant dans l'environnement.");
  process.exit(1);
}

function slotToPort(slot) {
  return BASE_PORT + slot;
}
function slotToContainerName(slot) {
  return `webtop-session-${slot}`;
}
function slotToDomain(slot) {
  if (PUBLIC_DOMAIN) return `u${slot}.${PUBLIC_DOMAIN}`;
  return `${DUCKDNS_PREFIX}${slot}.duckdns.org`;
}

function touchLastActive(trigram) {
  let store = {};
  try {
    store = JSON.parse(fs.readFileSync(LAST_ACTIVE_FILE, "utf8"));
  } catch {}
  store[trigram] = Date.now();
  try {
    fs.mkdirSync(require("path").dirname(LAST_ACTIVE_FILE), { recursive: true });
    fs.writeFileSync(LAST_ACTIVE_FILE, JSON.stringify(store, null, 2));
  } catch (err) {
    console.error("Impossible d'ecrire last-active.json:", err.message);
  }
}

function sanitizeTrigram(raw) {
  const t = String(raw || "").toLowerCase().trim();
  if (!/^[a-z0-9]{2,12}$/.test(t)) return null;
  return t;
}

// Valide l'URL du site à ouvrir (bouton IA ou champ "Autre"). Passe ensuite
// par une variable d'environnement Docker (jamais interpolée dans un shell
// ou un fichier .desktop côté conteneur), donc pas de risque d'injection —
// on valide surtout ici pour rejeter les URLs manifestement invalides tôt.
function sanitizeUrl(raw) {
  const s = String(raw || "").trim();
  if (!s || s.length > 2000 || /[\x00-\x1f\x7f]/.test(s)) return null;
  let u;
  try {
    u = new URL(s);
  } catch {
    return null;
  }
  if (u.protocol !== "http:" && u.protocol !== "https:") return null;
  return u.toString();
}

function dockerRequest(method, path, body) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const req = http.request(
      {
        socketPath: "/var/run/docker.sock",
        path,
        method,
        headers: data
          ? { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(data) }
          : {},
      },
      (res) => {
        let chunks = "";
        res.on("data", (c) => (chunks += c));
        res.on("end", () => {
          let parsed = null;
          try {
            parsed = chunks ? JSON.parse(chunks) : null;
          } catch (e) {
            parsed = chunks;
          }
          resolve({ statusCode: res.statusCode, body: parsed });
        });
      }
    );
    req.on("error", reject);
    if (data) req.write(data);
    req.end();
  });
}

async function dockerCreate(name, port, volumeName, targetUrl) {
  const r = await dockerRequest("POST", `/containers/create?name=${name}`, {
    Image: IMAGE,
    Env: ["PUID=1000", "PGID=1000", "TZ=Europe/Paris", `TARGET_URL=${targetUrl}`],
    HostConfig: {
      Memory: 1200 * 1024 * 1024,
      NanoCpus: 1_000_000_000,
      PortBindings: { "3000/tcp": [{ HostIp: "127.0.0.1", HostPort: String(port) }] },
      Binds: [`${volumeName}:/config`],
    },
    ExposedPorts: { "3000/tcp": {} },
  });
  if (r.statusCode !== 201) {
    throw new Error(`docker create ${name} a échoué (${r.statusCode}): ${JSON.stringify(r.body)}`);
  }
}

async function dockerStart(name) {
  const r = await dockerRequest("POST", `/containers/${name}/start`);
  if (r.statusCode !== 204 && r.statusCode !== 304) {
    throw new Error(`docker start ${name} a échoué (${r.statusCode}): ${JSON.stringify(r.body)}`);
  }
}

async function dockerStopAndRemove(name) {
  await dockerRequest("POST", `/containers/${name}/stop`).catch(() => {});
  await dockerRequest("DELETE", `/containers/${name}?force=true`).catch(() => {});
}

async function dockerContainerExists(name) {
  const r = await dockerRequest("GET", `/containers/${name}/json`);
  return r.statusCode === 200;
}

function waitForPort(port, timeoutMs = 25000) {
  return new Promise((resolve, reject) => {
    const start = Date.now();
    (function attempt() {
      const socket = net.connect({ host: "127.0.0.1", port }, () => {
        socket.end();
        resolve();
      });
      socket.on("error", () => {
        socket.destroy();
        if (Date.now() - start > timeoutMs) {
          reject(new Error(`Timeout en attendant le port ${port}`));
        } else {
          setTimeout(attempt, 500);
        }
      });
    })();
  });
}

function hasEstablishedConnection(port) {
  try {
    const out = execSync(
      `ss -Htn state established '( dport = :${port} or sport = :${port} )'`,
      { encoding: "utf8" }
    );
    return out.trim().length > 0;
  } catch (e) {
    return false;
  }
}

function sendJson(res, status, obj) {
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(JSON.stringify(obj));
}

// État en mémoire : slot -> { trigram, containerName, lastActive }
const slotState = {};
// Index inverse : trigram -> slot
const trigramToSlot = {};

function firstFreeSlot() {
  for (let slot = 1; slot <= SLOT_COUNT; slot++) {
    if (!slotState[slot]) return slot;
  }
  return null;
}

async function assignTrigram(trigram, targetUrl) {
  // Déjà en session active sur le même site ? On la réutilise (évite de
  // perdre le travail en cours). Si le site demandé diffère, la session
  // existante est remplacée par une nouvelle (le profil/volume persiste,
  // seuls le conteneur et son site affiché changent).
  const existingSlot = trigramToSlot[trigram];
  if (existingSlot && slotState[existingSlot] && (await dockerContainerExists(slotState[existingSlot].containerName))) {
    if (slotState[existingSlot].targetUrl === targetUrl) {
      slotState[existingSlot].lastActive = Date.now();
      touchLastActive(trigram);
      return existingSlot;
    }
    await releaseSlot(existingSlot);
  }

  const runningCount = Object.keys(slotState).length;
  if (runningCount >= MAX_CONCURRENT) {
    const err = new Error("capacity");
    err.code = "capacity";
    throw err;
  }

  const slot = firstFreeSlot();
  if (slot === null) {
    const err = new Error("capacity");
    err.code = "capacity";
    throw err;
  }

  const name = slotToContainerName(slot);
  const volumeName = `webtop-data-${trigram}`;
  const port = slotToPort(slot);

  await dockerCreate(name, port, volumeName, targetUrl);
  await dockerStart(name);
  await waitForPort(port);

  slotState[slot] = { trigram, containerName: name, lastActive: Date.now(), targetUrl };
  trigramToSlot[trigram] = slot;
  touchLastActive(trigram);

  return slot;
}

async function releaseSlot(slot) {
  const state = slotState[slot];
  if (!state) return;
  await dockerStopAndRemove(state.containerName);
  delete trigramToSlot[state.trigram];
  delete slotState[slot];
}

const server = http.createServer(async (req, res) => {
  const auth = req.headers["authorization"] || "";
  if (auth !== `Bearer ${SECRET}`) {
    return sendJson(res, 401, { error: "unauthorized" });
  }

  const url = new URL(req.url, "http://localhost");
  const parts = url.pathname.split("/").filter(Boolean);

  try {
    if (req.method === "POST" && parts[0] === "assign" && parts[1]) {
      const trigram = sanitizeTrigram(parts[1]);
      if (!trigram) return sendJson(res, 400, { error: "invalid_trigram" });

      const targetUrl = sanitizeUrl(url.searchParams.get("url"));
      if (!targetUrl) return sendJson(res, 400, { error: "invalid_url" });

      let slot;
      try {
        slot = await assignTrigram(trigram, targetUrl);
      } catch (err) {
        if (err.code === "capacity") {
          return sendJson(res, 503, {
            error: "capacity",
            message: "Tous les bureaux sont occupés, réessaie dans quelques minutes.",
          });
        }
        throw err;
      }

      return sendJson(res, 200, {
        ok: true,
        domain: slotToDomain(slot),
      });
    }

    if (req.method === "GET" && parts[0] === "status") {
      const slots = [];
      for (let slot = 1; slot <= SLOT_COUNT; slot++) {
        slots.push({ slot, ...(slotState[slot] || { trigram: null, lastActive: null }) });
      }
      return sendJson(res, 200, { slots, maxConcurrent: MAX_CONCURRENT });
    }

    sendJson(res, 404, { error: "not_found" });
  } catch (err) {
    console.error(err);
    sendJson(res, 500, { error: "internal", message: String((err && err.message) || err) });
  }
});

// Au démarrage, l'état des slots (slotState) repart à zéro en mémoire, mais
// un conteneur webtop-session-N d'une session précédente peut encore
// tourner côté Docker (redémarrage du service pendant une session active).
// Sans nettoyage, la prochaine tentative d'assignation sur ce slot échoue
// avec un conflit de nom. On supprime ici tout conteneur webtop-session-*
// orphelin (aucune donnée perdue : le volume webtop-data-<trigramme> n'est
// jamais touché).
async function reconcileOrphanContainers() {
  const filters = encodeURIComponent(JSON.stringify({ name: ["webtop-session-"] }));
  const r = await dockerRequest("GET", `/containers/json?all=true&filters=${filters}`);
  if (r.statusCode !== 200 || !Array.isArray(r.body)) return;
  for (const c of r.body) {
    const name = String((c.Names && c.Names[0]) || "").replace(/^\//, "");
    if (!/^webtop-session-\d+$/.test(name)) continue;
    console.log(`Nettoyage du conteneur orphelin ${name} (reste d'un redémarrage précédent)`);
    await dockerStopAndRemove(name);
  }
}

reconcileOrphanContainers()
  .catch((err) => console.error("Erreur lors du nettoyage des conteneurs orphelins:", err.message))
  .finally(() => {
    server.listen(PORT, "127.0.0.1", () => {
      console.log(`Orchestrateur en écoute sur 127.0.0.1:${PORT} (${SLOT_COUNT} slots, max ${MAX_CONCURRENT} simultanés)`);
    });
  });

// Coupe (et supprime) les conteneurs inactifs depuis plus de IDLE_MINUTES.
// Le volume de la personne n'est jamais touché : ses données persistent.
setInterval(async () => {
  for (const slot of Object.keys(slotState).map(Number)) {
    try {
      const state = slotState[slot];
      if (!state) continue;

      if (hasEstablishedConnection(slotToPort(slot))) {
        state.lastActive = Date.now();
        continue;
      }

      if (Date.now() - state.lastActive > IDLE_MINUTES * 60 * 1000) {
        console.log(`Slot ${slot} (${state.trigram}) inactif depuis ${IDLE_MINUTES} min, libération`);
        await releaseSlot(slot);
      }
    } catch (err) {
      console.error(`Erreur reaper slot ${slot}:`, err.message);
    }
  }
}, 60 * 1000);
