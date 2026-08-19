# Appli Bureau IA

Portail web (Next.js + Supabase Auth, hébergé sur Vercel) qui donne accès,
une fois connecté, à un bureau distant complet — pour naviguer sur des sites
depuis une machine différente de la sienne. Chaque utilisateur dispose de
son propre bureau isolé (conteneur Docker), démarré à la demande sur un
serveur maison.

## Développement local

```bash
npm install
cp .env.example .env.local   # puis renseigne les variables
npm run dev
```

## Déploiement

Voir [infra-home/README.md](infra-home/README.md) pour le guide complet
(actif) : serveur maison Ubuntu, conteneurs Docker "webtop" par utilisateur,
orchestrateur de démarrage/arrêt à la demande, table Supabase `profiles`,
DuckDNS, et variables Vercel.

[infra/README.md](infra/README.md) documente l'ancien système mono-utilisateur
(VM Google Cloud) — toujours fonctionnel indépendamment, mais plus branché
sur le portail.

## Architecture

- `app/login` — connexion Supabase (email + mot de passe)
- `app/dashboard` — page protégée, bouton "Ouvrir mon bureau distant"
- `app/api/vm-access` — regarde le slot assigné à l'utilisateur connecté
  (table Supabase `profiles`), demande à l'orchestrateur de démarrer son
  conteneur, renvoie l'URL + les identifiants de son bureau dédié
- `middleware.ts` — protège `/dashboard` et `/api/vm-access`
- `infra-home/` — serveur maison multi-utilisateurs (Docker, orchestrateur
  Node.js, Caddy, DuckDNS) — voir son README pour la mise en place complète
- `infra/` — ancien système mono-utilisateur (VM Google Cloud, Xfce +
  TigerVNC + noVNC + Caddy)
