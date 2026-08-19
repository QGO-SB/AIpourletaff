#!/usr/bin/env bash
# À exécuter UNE FOIS sur le serveur maison (Ubuntu Server), via SSH, avec sudo :
#   chmod +x setup-home-server.sh
#   sudo DUCKDNS_PREFIX=vm-ia DUCKDNS_TOKEN=xxxxx ./setup-home-server.sh
#
# Variables d'environnement acceptées :
#   DUCKDNS_PREFIX  (obligatoire) préfixe des sous-domaines DuckDNS déjà créés :
#                   ${DUCKDNS_PREFIX}1.duckdns.org ... ${DUCKDNS_PREFIX}${SLOT_COUNT}.duckdns.org
#                   (DuckDNS gratuit est limité à 5 sous-domaines : pas de domaine séparé
#                   pour l'orchestrateur, son API est servie sous /orch-api sur le slot 1)
#                   Note : DuckDNS traite les noms en minuscules quoi que tu tapes.
#   DUCKDNS_TOKEN   (obligatoire) token DuckDNS (visible sur duckdns.org une fois connecté)
#   ORCH_SECRET     (optionnel) secret partagé avec Vercel ; généré aléatoirement si absent
#   SLOT_COUNT      (optionnel, défaut 5) nombre d'emplacements de bureau simultanés possibles
#   MAX_CONCURRENT  (optionnel, défaut 5) nombre de bureaux actifs simultanés max
#   IDLE_MINUTES    (optionnel, défaut 15) inactivité avant libération auto d'un slot
#
# Le script est idempotent : on peut le relancer sans casser une install existante.
#
# Modèle : les "slots" sont de simples emplacements de calcul interchangeables
# (port + RAM/CPU réservés). Chaque personne s'identifie par un trigramme
# libre (ex. "qgo") côté portail — son volume Docker ("webtop-data-<trigramme>")
# est créé automatiquement au premier usage et la suit d'un slot à l'autre.
# Rien à enregistrer à l'avance.

set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Lance ce script avec sudo." >&2
  exit 1
fi

: "${DUCKDNS_PREFIX:?Il faut définir DUCKDNS_PREFIX=vm-ia (ou le préfixe de ton choix)}"
: "${DUCKDNS_TOKEN:?Il faut définir DUCKDNS_TOKEN=... (visible sur duckdns.org)}"

SLOT_COUNT="${SLOT_COUNT:-5}"
MAX_CONCURRENT="${MAX_CONCURRENT:-5}"
IDLE_MINUTES="${IDLE_MINUTES:-15}"
BASE_PORT=3000
WEBTOP_IMAGE="webtop-firefox:local"
CREDS_FILE="/etc/slot-credentials.csv"
ORCH_SECRET="${ORCH_SECRET:-$(head -c 24 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)}"

DESKTOP_USER="${SUDO_USER:-user1}"
INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Utilisateur          : $DESKTOP_USER"
echo "==> Slots                : $SLOT_COUNT (max $MAX_CONCURRENT simultanés)"
echo "==> Préfixe DuckDNS      : $DUCKDNS_PREFIX"

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

echo "==> Construction de l'image webtop + Firefox (une seule fois, réutilisée pour chaque session)"
docker build -t "$WEBTOP_IMAGE" "$INFRA_DIR/docker"

echo "==> Configuration de l'orchestrateur (/etc/orchestrator.env)"
cat > /etc/orchestrator.env <<EOF
ORCH_SECRET=${ORCH_SECRET}
ORCH_PORT=8080
SLOT_COUNT=${SLOT_COUNT}
BASE_PORT=${BASE_PORT}
WEBTOP_IMAGE=${WEBTOP_IMAGE}
MAX_CONCURRENT=${MAX_CONCURRENT}
IDLE_MINUTES=${IDLE_MINUTES}
DUCKDNS_PREFIX=${DUCKDNS_PREFIX}
CREDS_FILE=${CREDS_FILE}
EOF
chmod 600 /etc/orchestrator.env

echo "==> Identifiants Basic Auth par slot (défense en profondeur en plus de l'URL secrète)"
touch "$CREDS_FILE"
chown "root:$DESKTOP_USER" "$CREDS_FILE"
chmod 640 "$CREDS_FILE"

get_or_create_password() {
  local slot="$1"
  local existing
  existing=$(grep "^${slot}," "$CREDS_FILE" | cut -d',' -f3)
  if [[ -n "$existing" ]]; then
    echo "$existing"
    return
  fi
  local pass
  pass=$(head -c 18 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 20)
  echo "${slot},slot${slot},${pass}" >> "$CREDS_FILE"
  echo "$pass"
}

echo "==> Génération du Caddyfile ($SLOT_COUNT sous-domaines ; API orchestrateur sous /orch-api et portail sous /portal sur le slot 1)"
{
  for slot in $(seq 1 "$SLOT_COUNT"); do
    port=$((BASE_PORT + slot))
    pass=$(get_or_create_password "$slot")
    hash=$(caddy hash-password --plaintext "$pass")

    if [[ "$slot" -eq 1 ]]; then
      cat <<EOF2
${DUCKDNS_PREFIX}${slot}.duckdns.org {
	redir /portal /portal/

	handle_path /orch-api/* {
		reverse_proxy 127.0.0.1:8080
	}
	handle /portal/* {
		reverse_proxy 127.0.0.1:3900
	}
	handle {
		basicauth {
			slot${slot} ${hash}
		}
		reverse_proxy 127.0.0.1:${port}
	}
}

EOF2
    else
      cat <<EOF2
${DUCKDNS_PREFIX}${slot}.duckdns.org {
	basicauth {
		slot${slot} ${hash}
	}
	reverse_proxy 127.0.0.1:${port}
}

EOF2
    fi
  done
} > /etc/caddy/Caddyfile

systemctl enable --now caddy
systemctl restart caddy

echo "==> Service systemd de l'orchestrateur"
sed -e "s/__USER__/$DESKTOP_USER/g" \
    -e "s#__ORCH_DIR__#${INFRA_DIR}/orchestrator#g" \
    "$INFRA_DIR/systemd/orchestrator.service" > /etc/systemd/system/orchestrator.service
systemctl daemon-reload
systemctl enable --now orchestrator
systemctl restart orchestrator

echo "==> Mise à jour automatique DuckDNS (IPv6 — l'IPv4 est derrière un CGNAT SFR, inutilisable)"
DOMAINS="${DUCKDNS_PREFIX}1"
for slot in $(seq 2 "$SLOT_COUNT"); do
  DOMAINS="${DOMAINS},${DUCKDNS_PREFIX}${slot}"
done

cat > /usr/local/bin/duckdns-update.sh <<EOF
#!/usr/bin/env bash
IPV6=\$(ip -6 route get 2606:4700:4700::1111 2>/dev/null | grep -oP 'src \K\S+')
curl -fsS "https://www.duckdns.org/update?domains=${DOMAINS}&token=${DUCKDNS_TOKEN}&ipv6=\${IPV6}" -o /var/log/duckdns.log
EOF
chmod +x /usr/local/bin/duckdns-update.sh
( crontab -l 2>/dev/null | grep -v duckdns-update ; echo "*/5 * * * * /usr/local/bin/duckdns-update.sh" ) | crontab -
/usr/local/bin/duckdns-update.sh

cat <<EOF

==> Terminé.

Secret de l'orchestrateur (à mettre dans .env.production en tant que ORCHESTRATOR_SECRET) :
  ${ORCH_SECRET}

Le portail est maintenant auto-hébergé ici (plus Vercel, qui n'a pas de
sortie IPv6) : crée .env.production à la racine du repo (voir
infra-home/README.md), puis lance :
  ./infra-home/deploy-portal.sh

Une fois déployé, le portail sera sur :
  https://${DUCKDNS_PREFIX}1.duckdns.org/portal

Pense à :
  1. Autoriser les ports 80/443 en entrée IPv6 dans le pare-feu de ta box vers
     l'adresse IPv6 de ce serveur (pas de redirection de port en IPv6, juste
     une autorisation — voir infra-home/README.md)
  2. Créer les $SLOT_COUNT sous-domaines sur duckdns.org s'ils n'existent pas encore :
     ${DOMAINS}
  3. Créer .env.production et lancer ./infra-home/deploy-portal.sh (ci-dessus)

Rien d'autre à faire : chacun choisit son trigramme directement dans le portail,
son bureau (et son volume persistant) se crée tout seul au premier usage.

EOF
