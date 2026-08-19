#!/usr/bin/env bash
# À exécuter UNE FOIS sur la VM Oracle Cloud (Ubuntu 22.04 ou 24.04), via SSH, avec sudo :
#   chmod +x setup-vm.sh
#   sudo DOMAIN=toinom.duckdns.org BASIC_USER=monlogin ./setup-vm.sh
#
# Variables d'environnement acceptées :
#   DOMAIN       (obligatoire) nom DuckDNS pointant vers l'IP publique de la VM
#   BASIC_USER   (obligatoire) identifiant Basic Auth pour protéger le bureau
#   VNC_PASSWORD (optionnel) mot de passe VNC ; si absent, demandé via vncpasswd
#
# Le script est idempotent : on peut le relancer sans casser une install existante.

set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Lance ce script avec sudo." >&2
  exit 1
fi

: "${DOMAIN:?Il faut définir DOMAIN=toinom.duckdns.org}"
: "${BASIC_USER:?Il faut définir BASIC_USER=un_identifiant}"

DESKTOP_USER="${SUDO_USER:-ubuntu}"
DESKTOP_HOME=$(getent passwd "$DESKTOP_USER" | cut -d: -f6)
INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Utilisateur bureau : $DESKTOP_USER ($DESKTOP_HOME)"
echo "==> Domaine            : $DOMAIN"

echo "==> Fichier swap (nécessaire sur les shapes à faible RAM, ex. E2.1.Micro 1 Go)"
if [[ ! -f /swapfile ]]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  # Sur peu de RAM, on préfère swapper tôt plutôt que de laisser l'OOM killer agir
  sysctl -w vm.swappiness=60
  echo 'vm.swappiness=60' > /etc/sysctl.d/99-swappiness.conf
else
  echo "    (déjà présent, on ne touche pas)"
fi

echo "==> Mise à jour des paquets et installation (Xfce, TigerVNC, noVNC, Caddy)"
apt-get update -y
apt-get install -y \
  xfce4 \
  tigervnc-standalone-server tigervnc-common \
  novnc websockify \
  curl gnupg2 debian-keyring debian-archive-keyring apt-transport-https wget

if ! command -v firefox >/dev/null 2>&1 || snap list firefox >/dev/null 2>&1; then
  echo "==> Installation de Firefox via le dépôt APT officiel Mozilla (évite le snap, beaucoup plus lourd/lent)"
  install -d -m 0755 /etc/apt/keyrings
  wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- \
    | tee /etc/apt/keyrings/packages.mozilla.org.asc > /dev/null
  echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" \
    > /etc/apt/sources.list.d/mozilla.list
  printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' \
    > /etc/apt/preferences.d/mozilla
  apt-get update -y
  apt-get install -y firefox
fi

if ! command -v caddy >/dev/null 2>&1; then
  echo "==> Installation de Caddy (dépôt officiel)"
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -y
  apt-get install -y caddy
fi

echo "==> Configuration du serveur VNC pour $DESKTOP_USER"
sudo -u "$DESKTOP_USER" mkdir -p "$DESKTOP_HOME/.vnc"

cat > "$DESKTOP_HOME/.vnc/xstartup" <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startxfce4
EOF
chmod +x "$DESKTOP_HOME/.vnc/xstartup"
chown "$DESKTOP_USER":"$DESKTOP_USER" "$DESKTOP_HOME/.vnc/xstartup"

if [[ -n "${VNC_PASSWORD:-}" ]]; then
  sudo -u "$DESKTOP_USER" bash -c "echo '$VNC_PASSWORD' | vncpasswd -f > '$DESKTOP_HOME/.vnc/passwd'"
  chmod 600 "$DESKTOP_HOME/.vnc/passwd"
  chown "$DESKTOP_USER":"$DESKTOP_USER" "$DESKTOP_HOME/.vnc/passwd"
else
  echo "==> Définis le mot de passe VNC (utilisé uniquement en local, en plus du Basic Auth) :"
  sudo -u "$DESKTOP_USER" vncpasswd
fi

echo "==> Installation des services systemd (vncserver@, novnc)"
sed "s/__USER__/$DESKTOP_USER/g" "$INFRA_DIR/systemd/vncserver.service" > /etc/systemd/system/vncserver@.service
cp "$INFRA_DIR/systemd/novnc.service" /etc/systemd/system/novnc.service

systemctl daemon-reload
systemctl enable --now "vncserver@1.service"
systemctl enable --now novnc.service

echo "==> Génération du hash Basic Auth pour Caddy"
if [[ -n "${BASIC_PASSWORD:-}" ]]; then
  HASHED=$(caddy hash-password --plaintext "$BASIC_PASSWORD")
else
  read -rsp "Mot de passe Basic Auth pour $BASIC_USER : " BASIC_PASSWORD
  echo
  HASHED=$(caddy hash-password --plaintext "$BASIC_PASSWORD")
fi

echo "==> Écriture du Caddyfile (/etc/caddy/Caddyfile)"
sed -e "s/__DOMAIN__/$DOMAIN/g" \
    -e "s/__BASIC_USER__/$BASIC_USER/g" \
    -e "s#__BASIC_HASH__#$HASHED#g" \
    "$INFRA_DIR/Caddyfile" > /etc/caddy/Caddyfile

systemctl enable --now caddy
systemctl restart caddy

if command -v iptables >/dev/null 2>&1; then
  echo "==> Ouverture des ports 80/443 (iptables) — le port noVNC (6080) reste local uniquement"
  iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport 80 -j ACCEPT
  iptables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport 443 -j ACCEPT
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save
  fi
else
  echo "==> iptables absent (image minimale) — on saute cette étape : le firewall"
  echo "    réseau du cloud (Security List Oracle / VPC firewall Google) suffit,"
  echo "    tant que seuls les ports 80/443 y sont ouverts."
fi

cat <<EOF

==> Terminé.

Pense à vérifier que les ports 80 et 443 sont bien ouverts dans le firewall
réseau de ton cloud (Security List Oracle Cloud, ou VPC firewall / cases
"Allow HTTP/HTTPS traffic" sur Google Cloud) : sans ça, le trafic est
bloqué avant même d'atteindre la VM.

Une fois le DNS DuckDNS propagé, teste :
  https://$DOMAIN

EOF
