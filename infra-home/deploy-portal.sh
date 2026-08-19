#!/usr/bin/env bash
# Build et déploie le portail Next.js directement sur le serveur maison
# (plus besoin de Vercel : Vercel n'a pas de connectivité sortante IPv6,
# et l'orchestrateur n'est joignable qu'en IPv6 derrière le CGNAT SFR).
#
# À lancer depuis la racine du repo, une première fois via setup-home-server.sh
# puis à chaque mise à jour du code :
#   ./infra-home/deploy-portal.sh
#
# Nécessite un fichier .env.production à la racine du repo (voir
# infra-home/README.md) avec NEXT_PUBLIC_SUPABASE_URL,
# NEXT_PUBLIC_SUPABASE_ANON_KEY, ORCHESTRATOR_URL, ORCHESTRATOR_SECRET.

set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$APP_DIR"

if [[ ! -f .env.production ]]; then
  echo "Il manque .env.production à la racine du repo (voir infra-home/README.md)." >&2
  exit 1
fi

echo "==> Installation des dépendances"
npm install

echo "==> Build de production"
npm run build

echo "==> Copie des assets statiques dans le build standalone"
cp -r .next/static .next/standalone/.next/static
if [[ -d public ]]; then
  cp -r public .next/standalone/public
fi

echo "==> Installation/mise à jour du service systemd portal"
sudo sed -e "s/__USER__/$(whoami)/g" \
    -e "s#__APP_DIR__#${APP_DIR}#g" \
    "$APP_DIR/infra-home/systemd/portal.service" > /tmp/portal.service
sudo mv /tmp/portal.service /etc/systemd/system/portal.service
sudo systemctl daemon-reload
sudo systemctl enable --now portal
sudo systemctl restart portal

echo "==> Terminé. Portail disponible sous /portal sur le domaine du slot 1."
