// Orchestrateur : démarre/arrête à la demande les conteneurs Docker "webtop"
// (un par ami) et coupe ceux qui sont inactifs. Aucune dépendance npm :
// parle directement à l'API Docker via le socket Unix /var/run/docker.sock.

const http = require("http");
const net = require("net");
const { execSync } = require("child_process");

const SLOT_COUNT = parseInt(process.env.SLOT_COUNT || "10", 10);
const BASE_PORT = parseInt(process.env.BASE_PORT || "3000", 10);
const CONTAINER_PREFIX = process.env.CONTAINER_PREFIX || "webtop-slot-";
const MAX_CONCURRENT = parseInt(process.env.MAX_CONCURRENT || "5", 10);
const IDLE_MINUTES = parseInt(process.env.IDLE_MINUTES || "15", 10);
const SECRET = process.env.ORCH_SECRET;
const PORT = parseInt(process.env.ORCH_PORT || "8080", 10);

if (!SECRET) {
  console.error("ORCH_SECRET manquant dans l'environnement.");
  process.exit(1);
}

function slotToContainer(slot) {
  return `${CONTAINER_PREFIX}${slot}`;
}
function slotToPort(slot) {
  return BASE_PORT + slot;
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

async function dockerStart(name) {
  const r = await dockerRequest("POST", `/containers/${name}/start`);
  if (r.statusCode !== 204 && r.statusCode !== 304) {
    throw new Error(`docker start ${name} a échoué (${r.statusCode}): ${JSON.stringify(r.body)}`);
  }
}

async function dockerStop(name) {
  const r = await dockerRequest("POST", `/containers/${name}/stop`);
  if (r.statusCode !== 204 && r.statusCode !== 304) {
    throw new Error(`docker stop ${name} a échoué (${r.statusCode}): ${JSON.stringify(r.body)}`);
  }
}

async function dockerIsRunning(name) {
  const r = await dockerRequest("GET", `/containers/${name}/json`);
  if (r.statusCode === 404) return false;
  return !!(r.body && r.body.State && r.body.State.Running);
}

async function dockerRunningManagedCount() {
  const filters = encodeURIComponent(JSON.stringify({ name: [CONTAINER_PREFIX] }));
  const r = await dockerRequest("GET", `/containers/json?filters=${filters}`);
  return Array.isArray(r.body) ? r.body.length : 0;
}

function waitForPort(port, timeoutMs = 20000) {
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

const lastActive = {};

const server = http.createServer(async (req, res) => {
  const auth = req.headers["authorization"] || "";
  if (auth !== `Bearer ${SECRET}`) {
    return sendJson(res, 401, { error: "unauthorized" });
  }

  const url = new URL(req.url, "http://localhost");
  const parts = url.pathname.split("/").filter(Boolean);

  try {
    if (req.method === "POST" && parts[0] === "start" && parts[1]) {
      const slot = parseInt(parts[1], 10);
      if (!(slot >= 1 && slot <= SLOT_COUNT)) return sendJson(res, 400, { error: "invalid_slot" });

      const name = slotToContainer(slot);
      const alreadyRunning = await dockerIsRunning(name);

      if (!alreadyRunning) {
        const runningCount = await dockerRunningManagedCount();
        if (runningCount >= MAX_CONCURRENT) {
          return sendJson(res, 503, {
            error: "capacity",
            message: "Tous les bureaux sont occupés, réessaie dans quelques minutes.",
          });
        }
      }

      await dockerStart(name);
      await waitForPort(slotToPort(slot));
      lastActive[slot] = Date.now();
      return sendJson(res, 200, { ok: true, slot });
    }

    if (req.method === "POST" && parts[0] === "stop" && parts[1]) {
      const slot = parseInt(parts[1], 10);
      if (!(slot >= 1 && slot <= SLOT_COUNT)) return sendJson(res, 400, { error: "invalid_slot" });
      await dockerStop(slotToContainer(slot));
      return sendJson(res, 200, { ok: true });
    }

    if (req.method === "GET" && parts[0] === "status") {
      const slots = [];
      for (let slot = 1; slot <= SLOT_COUNT; slot++) {
        slots.push({
          slot,
          running: await dockerIsRunning(slotToContainer(slot)),
          lastActive: lastActive[slot] || null,
        });
      }
      return sendJson(res, 200, { slots });
    }

    sendJson(res, 404, { error: "not_found" });
  } catch (err) {
    console.error(err);
    sendJson(res, 500, { error: "internal", message: String((err && err.message) || err) });
  }
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`Orchestrateur en écoute sur 127.0.0.1:${PORT} (${SLOT_COUNT} slots, max ${MAX_CONCURRENT} simultanés)`);
});

// Coupe les conteneurs inactifs depuis plus de IDLE_MINUTES
setInterval(async () => {
  for (let slot = 1; slot <= SLOT_COUNT; slot++) {
    try {
      const name = slotToContainer(slot);
      const running = await dockerIsRunning(name);
      if (!running) continue;

      if (hasEstablishedConnection(slotToPort(slot))) {
        lastActive[slot] = Date.now();
        continue;
      }

      const last = lastActive[slot] || Date.now();
      if (Date.now() - last > IDLE_MINUTES * 60 * 1000) {
        console.log(`Slot ${slot} inactif depuis ${IDLE_MINUTES} min, arrêt du conteneur`);
        await dockerStop(name);
      }
    } catch (err) {
      console.error(`Erreur reaper slot ${slot}:`, err.message);
    }
  }
}, 60 * 1000);
