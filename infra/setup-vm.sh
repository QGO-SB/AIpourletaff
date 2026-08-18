#!/usr/bin/env bash
# À exécuter UNE FOIS sur la VM Oracle Cloud (Ubuntu 22.04), via SSH, avec sudo :
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

echo "==> Mise à jour des paquets et installation (Xfce, TigerVNC, noVNC, Firefox, Caddy)"
apt-get update -y
apt-get install -y \
  xfce4 xfce4-goodies \
  tigervnc-standalone-server tigervnc-common \
  novnc websockify \
  firefox \
  curl gnupg2 debian-keyring debian-archive-keyring apt-transport-https

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

echo "==> Ouverture des ports 80/443 (iptables) — le port noVNC (6080) reste local uniquement"
iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport 80 -j ACCEPT
iptables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport 443 -j ACCEPT
if command -v netfilter-persistent >/dev/null 2>&1; then
  netfilter-persistent save
fi

cat <<EOF

==> Terminé.

Pense à aussi ouvrir les ports 80 et 443 dans la "Security List" / "Network
Security Group" de ta VM sur la console Oracle Cloud (Networking > VCN) :
sans ça, le firewall du réseau bloquera le trafic même si iptables l'autorise
localement.

Une fois le DNS DuckDNS propagé, teste :
  https://$DOMAIN

EOF
