#!/usr/bin/env bash
# Change le mot de passe Basic Auth d'un slot, régénère le bloc Caddy
# correspondant et recharge Caddy. À lancer avec sudo, depuis le dossier
# infra-home (le même que setup-home-server.sh).
#
#   sudo ./set-slot-password.sh <slot> [nouveau_mot_de_passe]
#
# Sans mot de passe fourni, un mot de passe aléatoire est généré.

set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Lance ce script avec sudo." >&2
  exit 1
fi

SLOT="${1:?Usage: sudo ./set-slot-password.sh <slot> [mot_de_passe]}"
PASS="${2:-$(head -c 18 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 20)}"
CREDS_FILE="/etc/slot-credentials.csv"

if ! grep -q "^${SLOT}," "$CREDS_FILE" 2>/dev/null; then
  echo "Slot $SLOT introuvable dans $CREDS_FILE — lance d'abord setup-home-server.sh." >&2
  exit 1
fi

grep -v "^${SLOT}," "$CREDS_FILE" > "${CREDS_FILE}.tmp" || true
echo "${SLOT},slot${SLOT},${PASS}" >> "${CREDS_FILE}.tmp"
mv "${CREDS_FILE}.tmp" "$CREDS_FILE"

HASH=$(caddy hash-password --plaintext "$PASS")

if ! grep -q "slot${SLOT} " /etc/caddy/Caddyfile; then
  echo "Bloc pour slot ${SLOT} introuvable dans /etc/caddy/Caddyfile" >&2
  exit 1
fi
sed -i -E "s#(slot${SLOT} )\S+#\1${HASH}#" /etc/caddy/Caddyfile

systemctl reload caddy

echo "Nouveau mot de passe pour slot ${SLOT} (utilisateur slot${SLOT}) : ${PASS}"
echo "Pense à mettre à jour la colonne basic_pass dans Supabase pour cet ami."
