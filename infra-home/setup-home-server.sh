#!/usr/bin/env bash
# À exécuter UNE FOIS sur le serveur maison (Ubuntu Server), via SSH, avec sudo :
#   chmod +x setup-home-server.sh
#   sudo DUCKDNS_BASE=qgo DUCKDNS_TOKEN=xxxxx ./setup-home-server.sh
#
# Variables d'environnement acceptées :
#   DUCKDNS_BASE    (obligatoire) préfixe des sous-domaines DuckDNS déjà créés :
#                   ${DUCKDNS_BASE}-u1.duckdns.org ... ${DUCKDNS_BASE}-u${SLOT_COUNT}.duckdns.org
#                   + ${DUCKDNS_BASE}-orch.duckdns.org (API de l'orchestrateur)
#   DUCKDNS_TOKEN   (obligatoire) token DuckDNS (visible sur duckdns.org une fois connecté)
#   ORCH_SECRET     (optionnel) secret partagé avec Vercel ; généré aléatoirement si absent
#   SLOT_COUNT      (optionnel, défaut 10) nombre de bureaux à préparer
#   MAX_CONCURRENT  (optionnel, défaut 5) nombre de bureaux actifs simultanés max
#   IDLE_MINUTES    (optionnel, défaut 15) inactivité avant arrêt auto d'un bureau
#
# Le script est idempotent : on peut le relancer sans casser une install existante.

set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Lance ce script avec sudo." >&2
  exit 1
fi

: "${DUCKDNS_BASE:?Il faut définir DUCKDNS_BASE=qgo (ou le préfixe de ton choix)}"
: "${DUCKDNS_TOKEN:?Il faut définir DUCKDNS_TOKEN=... (visible sur duckdns.org)}"

SLOT_COUNT="${SLOT_COUNT:-10}"
MAX_CONCURRENT="${MAX_CONCURRENT:-5}"
IDLE_MINUTES="${IDLE_MINUTES:-15}"
BASE_PORT=3000
CONTAINER_PREFIX="webtop-slot-"
ORCH_SECRET="${ORCH_SECRET:-$(head -c 24 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)}"

DESKTOP_USER="${SUDO_USER:-user1}"
INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Utilisateur          : $DESKTOP_USER"
echo "==> Slots                : $SLOT_COUNT (max $MAX_CONCURRENT simultanés)"
echo "==> Base DuckDNS         : $DUCKDNS_BASE"

echo "==> Désactivation de cloud-init (inutile sur du matériel physique, évite un délai au boot)"
touch /etc/cloud/cloud-init.disabled

echo "==> Mise à jour des paquets"
apt-get update -y
apt-get install -y curl gnupg ca-certificates apt-transport-https iproute2 nodejs npm

if ! command -v docker >/dev/null 2>&1; then
  echo "==> Installation de Docker Engine (dépôt officiel)"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi
usermod -aG docker "$DESKTOP_USER"

if ! command -v caddy >/dev/null 2>&1; then
  echo "==> Installation de Caddy (dépôt officiel)"
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -y
  apt-get install -y caddy
fi

echo "==> Téléchargement de l'image webtop"
docker pull lscr.io/linuxserver/webtop:ubuntu-xfce

echo "==> Préparation des $SLOT_COUNT conteneurs (créés, pas démarrés — l'orchestrateur gère le cycle de vie)"
for slot in $(seq 1 "$SLOT_COUNT"); do
  name="${CONTAINER_PREFIX}${slot}"
  port=$((BASE_PORT + slot))

  if docker inspect "$name" >/dev/null 2>&1; then
    echo "    $name existe déjà, on ne recrée pas (garde les données persistantes)"
    continue
  fi

  echo "    Création de $name (port 127.0.0.1:$port)"
  docker create \
    --name "$name" \
    --memory=1200m --cpus=1 \
    -p "127.0.0.1:${port}:3000" \
    -e PUID=1000 -e PGID=1000 -e TZ=Europe/Paris \
    -e TITLE="Bureau distant" \
    -v "webtop-data-${slot}:/config" \
    lscr.io/linuxserver/webtop:ubuntu-xfce

  echo "    Installation de Firefox (dépôt Mozilla, pas de snap dans un conteneur) dans $name"
  docker start "$name" >/dev/null
  sleep 5
  docker exec "$name" bash -c '
    install -d -m 0755 /etc/apt/keyrings
    wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- | tee /etc/apt/keyrings/packages.mozilla.org.asc > /dev/null
    echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" > /etc/apt/sources.list.d/mozilla.list
    printf "Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n" > /etc/apt/preferences.d/mozilla
    apt-get update -y
    apt-get install -y --allow-downgrades firefox
  ' || echo "    (avertissement : install Firefox a échoué pour $name, à vérifier manuellement)"
  docker stop "$name" >/dev/null
done

echo "==> Configuration de l'orchestrateur (/etc/orchestrator.env)"
cat > /etc/orchestrator.env <<EOF
ORCH_SECRET=${ORCH_SECRET}
ORCH_PORT=8080
SLOT_COUNT=${SLOT_COUNT}
BASE_PORT=${BASE_PORT}
CONTAINER_PREFIX=${CONTAINER_PREFIX}
MAX_CONCURRENT=${MAX_CONCURRENT}
IDLE_MINUTES=${IDLE_MINUTES}
EOF
chmod 600 /etc/orchestrator.env

echo "==> Service systemd de l'orchestrateur"
sed -e "s/__USER__/$DESKTOP_USER/g" \
    -e "s#__ORCH_DIR__#${INFRA_DIR}/orchestrator#g" \
    "$INFRA_DIR/systemd/orchestrator.service" > /etc/systemd/system/orchestrator.service
systemctl daemon-reload
systemctl enable --now orchestrator

echo "==> Identifiants Basic Auth par slot (défense en profondeur en plus de l'URL secrète)"
CREDS_FILE="/etc/slot-credentials.csv"
touch "$CREDS_FILE"
chmod 600 "$CREDS_FILE"

get_or_create_password() {
  local slot="$1"
  local existing
  existing=$(grep "^${slot}," "$CREDS_FILE" | cut -d',' -f3)
  if [[ -n "$existing" ]]; then
    echo "$existing"
    return
  fi
  local user="slot${slot}"
  local pass
  pass=$(head -c 18 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 20)
  echo "${slot},${user},${pass}" >> "$CREDS_FILE"
  echo "$pass"
}

echo "==> Génération du Caddyfile ($SLOT_COUNT sous-domaines + 1 pour l'orchestrateur)"
{
  for slot in $(seq 1 "$SLOT_COUNT"); do
    port=$((BASE_PORT + slot))
    pass=$(get_or_create_password "$slot")
    hash=$(caddy hash-password --plaintext "$pass")
    cat <<EOF2
${DUCKDNS_BASE}-u${slot}.duckdns.org {
	basicauth {
		slot${slot} ${hash}
	}
	reverse_proxy 127.0.0.1:${port}
}

EOF2
  done
  cat <<EOF3
${DUCKDNS_BASE}-orch.duckdns.org {
	reverse_proxy 127.0.0.1:8080
}
EOF3
} > /etc/caddy/Caddyfile

systemctl enable --now caddy
systemctl restart caddy

echo "==> Mise à jour automatique DuckDNS (IP domestique probablement dynamique)"
DOMAINS="${DUCKDNS_BASE}-orch"
for slot in $(seq 1 "$SLOT_COUNT"); do
  DOMAINS="${DOMAINS},${DUCKDNS_BASE}-u${slot}"
done

cat > /usr/local/bin/duckdns-update.sh <<EOF
#!/usr/bin/env bash
curl -fsS "https://www.duckdns.org/update?domains=${DOMAINS}&token=${DUCKDNS_TOKEN}&ip=" -o /var/log/duckdns.log
EOF
chmod +x /usr/local/bin/duckdns-update.sh
( crontab -l 2>/dev/null | grep -v duckdns-update ; echo "*/5 * * * * /usr/local/bin/duckdns-update.sh" ) | crontab -
/usr/local/bin/duckdns-update.sh

cat <<EOF

==> Terminé.

Secret de l'orchestrateur (à mettre dans Vercel en tant que ORCHESTRATOR_SECRET) :
  ${ORCH_SECRET}

URL de l'orchestrateur (à mettre dans Vercel en tant que ORCHESTRATOR_URL) :
  https://${DUCKDNS_BASE}-orch.duckdns.org

Identifiants Basic Auth par slot (à recopier dans Supabase, voir infra-home/README.md) :
  cat ${CREDS_FILE}
  (format : slot,utilisateur,mot_de_passe)

Pense à :
  1. Configurer le port-forward 80/443 de ta box vers $(hostname -I | awk '{print $1}') si ce n'est pas déjà fait
  2. Créer les $((SLOT_COUNT + 1)) sous-domaines sur duckdns.org s'ils n'existent pas encore :
     ${DOMAINS}
  3. Pour chaque ami : ajouter une ligne dans la table Supabase "profiles" avec son slot, le domaine
     correspondant (${DUCKDNS_BASE}-uN.duckdns.org) et les identifiants du fichier ci-dessus

EOF
