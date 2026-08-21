#!/usr/bin/env bash
# Lance Firefox, fenêtre maximisée, directement sur le site de cette session
# (TARGET_URL, fourni par l'orchestrateur via une variable d'environnement).
firefox --new-window "${TARGET_URL:-https://claude.ai}" &
( sleep 2 && wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz ) &
