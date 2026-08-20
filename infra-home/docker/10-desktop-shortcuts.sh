#!/usr/bin/with-contenv bash
# Crée les raccourcis bureau vers les sites d'IA au premier démarrage du
# conteneur (idempotent : ne recrée pas un raccourci que l'utilisateur a
# supprimé ou modifié).

DESKTOP_DIR="/config/Desktop"
mkdir -p "$DESKTOP_DIR"

make_shortcut() {
  local name="$1"
  local url="$2"
  local file="$DESKTOP_DIR/${name}.desktop"

  if [ ! -f "$file" ]; then
    cat > "$file" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=${name}
Comment=Ouvrir ${name}
Exec=firefox --new-window ${url}
Icon=web-browser
Terminal=false
Categories=Network;
EOF
    chmod +x "$file"
  fi
}

make_shortcut "Claude" "https://claude.ai"
make_shortcut "ChatGPT" "https://chatgpt.com"
make_shortcut "Perplexity" "https://www.perplexity.ai"

chown -R abc:abc "$DESKTOP_DIR" 2>/dev/null || true
