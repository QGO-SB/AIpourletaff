# Appli Bureau IA

Portail web (Next.js + Supabase Auth, hébergé sur Vercel) qui donne accès,
une fois connecté, à un bureau distant complet tournant sur une VM gratuite
(Oracle Cloud Always Free), pour naviguer sur des sites depuis une machine
différente de la sienne.

## Développement local

```bash
npm install
cp .env.example .env.local   # puis renseigne les variables
npm run dev
```

## Déploiement

Voir [infra/README.md](infra/README.md) pour le guide complet : création de
la VM Oracle Cloud, DNS DuckDNS, configuration du bureau distant (Xfce +
TigerVNC + noVNC + Caddy), projet Supabase, et déploiement sur Vercel.

## Architecture

- `app/login` — connexion Supabase (email + mot de passe)
- `app/dashboard` — page protégée, bouton "Ouvrir mon bureau distant"
- `app/api/vm-access` — renvoie l'URL + les identifiants de la VM,
  uniquement si la session Supabase est valide
- `middleware.ts` — protège `/dashboard` et `/api/vm-access`
- `infra/` — scripts et configuration pour la VM (Xfce, TigerVNC, noVNC,
  Caddy en reverse proxy avec Basic Auth + HTTPS automatique)
