# Image webtop + Firefox (installé via le dépôt officiel Mozilla, pas de
# snap : ça ne fonctionne pas correctement dans un conteneur). Construite
# une fois par setup-home-server.sh, puis réutilisée par l'orchestrateur
# pour créer un conteneur éphémère par session.
FROM lscr.io/linuxserver/webtop:ubuntu-xfce

RUN install -d -m 0755 /etc/apt/keyrings && \
    wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- \
      | tee /etc/apt/keyrings/packages.mozilla.org.asc > /dev/null && \
    echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" \
      > /etc/apt/sources.list.d/mozilla.list && \
    printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' \
      > /etc/apt/preferences.d/mozilla && \
    apt-get update && \
    apt-get install -y --allow-downgrades firefox && \
    rm -rf /var/lib/apt/lists/*
