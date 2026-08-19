# Appli Bureau IA

Portail web (Next.js + Supabase Auth, auto-hébergé sur le serveur maison —
Vercel n'a pas de sortie réseau IPv6, nécessaire ici à cause du CGNAT de la
box) qui donne accès, une fois connecté, à un bureau distant complet — pour
naviguer sur des sites depuis une machine différente de la sienne. Chacun
s'identifie par un trigramme libre ; son bureau (conteneur Docker) et ses
données persistantes sont créés automatiquement au premier usage, démarrés
à la demande sur le même serveur maison.

## Développement local

```bash
npm install
cp .env.example .env.local   # puis renseigne les variables
npm run dev
```

## Déploiement

Voir [infra-home/README.md](infra-home/README.md) pour le guide complet
(actif) : serveur maison Ubuntu, image Docker "webtop" + Firefox,
orchestrateur de démarrage/arrêt à la demande par trigramme, DuckDNS/IPv6,
et déploiement auto-hébergé du portail lui-même (`infra-home/deploy-portal.sh`).

[infra/README.md](infra/README.md) documente l'ancien système mono-utilisateur
(VM Google Cloud) — toujours fonctionnel indépendamment, mais plus branché
sur le portail.

## Architecture

- `app/login` — connexion Supabase (compte partagé, email + mot de passe)
- `app/dashboard` — page protégée, saisie du trigramme + bouton "Ouvrir mon
  bureau distant"
- `app/api/vm-access` — vérifie la session Supabase, demande à
  l'orchestrateur d'assigner un slot au trigramme fourni, renvoie l'URL +
  les identifiants du bureau
- `middleware.ts` — protège `/dashboard` et `/api/vm-access`
- `infra-home/` — serveur maison multi-utilisateurs (Docker, orchestrateur
  Node.js, Caddy, DuckDNS) — voir son README pour la mise en place complète
- `infra/` — ancien système mono-utilisateur (VM Google Cloud, Xfce +
  TigerVNC + noVNC + Caddy)
