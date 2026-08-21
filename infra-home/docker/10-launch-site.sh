#!/usr/bin/with-contenv bash
# Démarre automatiquement Firefox sur le site demandé pour cette session
# (via start-browser.sh, qui lit TARGET_URL dans l'environnement) au lieu
# d'afficher le bureau XFCE complet. Réécrit à chaque démarrage du
# conteneur : contrairement aux anciens raccourcis bureau, cette entrée
# n'est pas destinée à être modifiée par la personne.

AUTOSTART_DIR="/config/.config/autostart"
mkdir -p "$AUTOSTART_DIR"

cat > "$AUTOSTART_DIR/site.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Site
Exec=/usr/local/bin/start-browser.sh
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF

chown -R abc:abc "$AUTOSTART_DIR" 2>/dev/null || true
