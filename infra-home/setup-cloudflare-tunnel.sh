#!/usr/bin/env bash
# Configure un tunnel Cloudflare pour rendre le serveur joignable en IPv4 ET
# IPv6 (Cloudflare est dual-stack), sans dépendre de la redirection de port
# IPv4 (impossible ici, CGNAT SFR) ni de l'IPv6 côté client (pas universel).
# Fonctionne EN PLUS de l'accès DuckDNS/IPv6 existant, ne le remplace pas.
#
# À lancer avec sudo, depuis infra-home/ :
#   sudo PUBLIC_DOMAIN=nitneuq.com ./setup-cloudflare-tunnel.sh
#
# Étape manuelle obligatoire AVANT de lancer ce script : authentifier
# cloudflared auprès de ton compte Cloudflare (ouvre un lien à valider dans
# un navigateur) :
#   sudo cloudflared tunnel login
# (installe cloudflared d'abord si besoin — ce script le fait aussi, donc tu
# peux le relancer après avoir fait le login si ça manque au premier essai)

set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Lance ce script avec sudo." >&2
  exit 1
fi

: "${PUBLIC_DOMAIN:?Il faut définir PUBLIC_DOMAIN=tondomaine.com}"

SLOT_COUNT="${SLOT_COUNT:-5}"
BASE_PORT="${BASE_PORT:-3000}"
TUNNEL_NAME="${TUNNEL_NAME:-bureau-tunnel}"

if ! command -v cloudflared >/dev/null 2>&1; then
  echo "==> Installation de cloudflared (dépôt officiel)"
  mkdir -p --mode=0755 /usr/share/keyrings
  curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg
  echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/cloudflared.list
  apt-get update -y
  apt-get install -y cloudflared
fi

if [[ ! -f /root/.cloudflared/cert.pem ]]; then
  cat <<EOF
==> Il faut d'abord t'authentifier auprès de Cloudflare (une seule fois) :
      sudo cloudflared tunnel login
    Ouvre le lien affiché dans un navigateur, choisis ${PUBLIC_DOMAIN}, puis
    relance ce script.
EOF
  exit 1
fi

EXISTING_ID=$(cloudflared tunnel list 2>/dev/null | awk -v name="$TUNNEL_NAME" '$2 == name {print $1}')
if [[ -n "$EXISTING_ID" ]]; then
  echo "==> Tunnel ${TUNNEL_NAME} existe déjà (${EXISTING_ID})"
  TUNNEL_ID="$EXISTING_ID"
else
  echo "==> Création du tunnel ${TUNNEL_NAME}"
  CREATE_OUTPUT=$(cloudflared tunnel create "$TUNNEL_NAME")
  echo "$CREATE_OUTPUT"
  TUNNEL_ID=$(echo "$CREATE_OUTPUT" | grep -oP 'with id \K[0-9a-f-]+')
fi

: "${TUNNEL_ID:?Impossible de déterminer l'ID du tunnel}"
CREDS_FILE="/root/.cloudflared/${TUNNEL_ID}.json"

echo "==> Génération de la config du tunnel (/etc/cloudflared/config.yml)"
mkdir -p /etc/cloudflared
{
  echo "tunnel: ${TUNNEL_ID}"
  echo "credentials-file: ${CREDS_FILE}"
  echo "ingress:"
  echo "  - hostname: bureau.${PUBLIC_DOMAIN}"
  echo "    service: http://127.0.0.1:3900"
  echo "  - hostname: orch.${PUBLIC_DOMAIN}"
  echo "    service: http://127.0.0.1:8080"
  for slot in $(seq 1 "$SLOT_COUNT"); do
    port=$((BASE_PORT + slot))
    echo "  - hostname: u${slot}.${PUBLIC_DOMAIN}"
    echo "    service: http://127.0.0.1:${port}"
  done
  echo "  - service: http_status:404"
} > /etc/cloudflared/config.yml

echo "==> Création des enregistrements DNS sur Cloudflare"
cloudflared tunnel route dns -f "$TUNNEL_NAME" "bureau.${PUBLIC_DOMAIN}"
cloudflared tunnel route dns -f "$TUNNEL_NAME" "orch.${PUBLIC_DOMAIN}"
for slot in $(seq 1 "$SLOT_COUNT"); do
  cloudflared tunnel route dns -f "$TUNNEL_NAME" "u${slot}.${PUBLIC_DOMAIN}"
done

echo "==> Installation du service systemd cloudflared"
cloudflared --config /etc/cloudflared/config.yml service install
systemctl enable --now cloudflared
systemctl restart cloudflared

cat <<EOF

==> Terminé.

Portail accessible sur :
  https://bureau.${PUBLIC_DOMAIN}/portal

Pense à mettre à jour /etc/orchestrator.env avec :
  PUBLIC_DOMAIN=${PUBLIC_DOMAIN}
puis : sudo systemctl restart orchestrator

EOF
