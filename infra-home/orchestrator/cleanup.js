// Supprime les volumes Docker (profils Firefox) des trigrammes inactifs
// depuis plus de RETENTION_DAYS. À lancer une fois par jour via cron —
// voir setup-home-server.sh. Aucune dépendance npm.

const fs = require("fs");
const { execSync } = require("child_process");

const RETENTION_DAYS = parseInt(process.env.RETENTION_DAYS || "30", 10);
const LAST_ACTIVE_FILE = process.env.LAST_ACTIVE_FILE || "/var/lib/orchestrator/last-active.json";

if (!fs.existsSync(LAST_ACTIVE_FILE)) {
  console.log("Pas de fichier d'activite, rien a faire.");
  process.exit(0);
}

const data = JSON.parse(fs.readFileSync(LAST_ACTIVE_FILE, "utf8"));
const cutoff = Date.now() - RETENTION_DAYS * 24 * 60 * 60 * 1000;
let changed = false;

for (const [trigram, lastActive] of Object.entries(data)) {
  if (lastActive >= cutoff) continue;

  const volume = `webtop-data-${trigram}`;
  try {
    execSync(`docker volume rm ${volume}`, { stdio: "pipe" });
    console.log(`Volume supprime (inactif depuis plus de ${RETENTION_DAYS} jours) : ${volume}`);
  } catch (err) {
    console.log(`Volume ${volume} : suppression differee (encore utilise ?) - ${String(err.message).split("\n")[0]}`);
    continue;
  }

  delete data[trigram];
  changed = true;
}

if (changed) {
  fs.writeFileSync(LAST_ACTIVE_FILE, JSON.stringify(data, null, 2));
}
