# Serveur maison multi-utilisateurs — guide pas-à-pas

Ce dossier configure le **serveur maison** (Ubuntu Server, connecté en Ethernet
à la box, IP locale réservée) qui fait tourner un bureau distant Docker par
personne, démarré à la demande, **et héberge aussi le portail Next.js**
lui-même. Indépendant de `infra/` (qui reste pour la VM Google Cloud
personnelle).

**Modèle** : un seul login Supabase partagé donne accès au portail. Une fois
connecté, chacun tape un **trigramme** libre (ex. "QGO") pour s'identifier —
son bureau et ses données (profil Firefox, historique, comptes connectés)
sont automatiquement créés au premier usage et le suivent d'une session à
l'autre, peu importe le slot physique attribué. Rien à enregistrer à l'avance.

**Sécurité** : l'accès aux bureaux n'est protégé que par le login Supabase
(pas de Basic Auth par slot — ça causait des boucles d'authentification
selon les navigateurs mobiles, notamment Chrome/Android). L'URL exacte d'un
bureau n'est révélée qu'après connexion au portail.

**Transfert de fichiers** : géré nativement par KasmVNC (le moteur d'affichage
de webtop) — pas besoin d'outil supplémentaire. L'icône dans la barre latérale
du bureau distant permet d'envoyer et récupérer des fichiers directement.

**Raccourcis bureau** : chaque session webtop démarre avec des icônes vers
Claude, ChatGPT et Perplexity (voir `infra-home/docker/10-desktop-shortcuts.sh`),
créées une seule fois par volume (l'utilisateur peut les supprimer/modifier
sans qu'elles soient recréées).

**Pourquoi le portail est auto-hébergé (pas Vercel)** : la box SFR (et
beaucoup de box fibre récentes) est derrière un **CGNAT** — pas de vraie IP
publique IPv4, donc aucune redirection de port IPv4 ne fonctionne. Le serveur
n'est donc joignable qu'en **IPv6** (natif chez la plupart des FAI/opérateurs
mobiles français). Or les fonctions serverless de Vercel n'ont pas de sortie
IPv6, donc elles ne peuvent pas contacter l'orchestrateur. Solution : tout
héberger au même endroit, plus besoin de traverser internet en interne.

## 1. Réseau du serveur

- Connecte le serveur en **Ethernet** à la box (plus fiable que le wifi pour
  un service permanent).
- Réserve son IP locale dans la box (bail DHCP statique sur son adresse MAC),
  pour qu'elle ne change jamais.
- Récupère son adresse IPv6 globale stable : `ip -6 route get 2606:4700:4700::1111`
  (le champ `src`).

## 2. Créer les sous-domaines DuckDNS

Va sur [duckdns.org](https://www.duckdns.org), connecte-toi, et crée un
sous-domaine par slot — avec le préfixe de ton choix (ex. `vm-ia`). DuckDNS
gratuit est limité à **5 sous-domaines**, donc pas de domaine séparé pour
l'orchestrateur ou le portail : ils sont servis sous `/orch-api` et `/portal`
sur le slot 1.

```
vm-ia1
vm-ia2
vm-ia3
vm-ia4
vm-ia5
```

Laisse l'IP à blanc pour l'instant (`setup-home-server.sh` mettra à jour
l'**IPv6** automatiquement via cron). Note ton **token DuckDNS** (en haut de
la page une fois connecté).

## 3. Autoriser 80/443 en IPv6 sur la box

Pas de redirection de port ici (l'IPv6 n'a pas de NAT) — juste une
**autorisation de pare-feu entrant IPv6** vers l'adresse IPv6 du serveur, sur
les ports 80 et 443 (TCP). Sur une box SFR : **Sécurité > Paramètres >
Redirection de ports > section "Réseau v6" > Créer une règle**.

## 4. Lancer le script sur le serveur

En SSH sur le serveur (`ssh -i ~/.ssh/home_server user1@<IP locale>` depuis
ce PC) :

```bash
git clone https://github.com/QGO-SB/AIpourletaff.git
cd AIpourletaff/infra-home
chmod +x setup-home-server.sh deploy-portal.sh
sudo DUCKDNS_PREFIX=vm-ia DUCKDNS_TOKEN=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx ./setup-home-server.sh
```

Ça prend un moment (construction de l'image Docker webtop + Firefox). À la
fin, le script affiche le secret de l'orchestrateur (`ORCHESTRATOR_SECRET`).

## 4bis. Tunnel Cloudflare (accès universel, IPv4 + IPv6)

L'accès DuckDNS/IPv6 ci-dessus ne fonctionne que pour les clients qui ont
l'IPv6 (la plupart des mobiles, pas tous les PC/box). Le tunnel Cloudflare
couvre tout le monde, en plus (pas à la place) — Cloudflare est dual-stack.
Nécessite un nom de domaine ajouté à Cloudflare (ex. via Cloudflare Registrar,
~10$/an).

1. Sur le serveur, authentifie `cloudflared` (une seule fois, ouvre un lien à
   valider dans un navigateur) :
   ```bash
   sudo cloudflared tunnel login
   ```
2. Lance le script :
   ```bash
   chmod +x setup-cloudflare-tunnel.sh
   sudo PUBLIC_DOMAIN=tondomaine.com ./setup-cloudflare-tunnel.sh
   ```
   Il installe `cloudflared`, crée le tunnel, les enregistrements DNS
   (`bureau.`, `orch.`, `u1.` à `u5.tondomaine.com`), et le service systemd.
3. Bascule l'orchestrateur sur ce domaine :
   ```bash
   sudo PUBLIC_DOMAIN=tondomaine.com DUCKDNS_PREFIX=vm-ia DUCKDNS_TOKEN=xxx ./setup-home-server.sh
   ```
   (relance normale du script principal, avec `PUBLIC_DOMAIN` en plus — dès
   qu'il est défini, l'orchestrateur donne des URLs `u{slot}.tondomaine.com`
   au lieu de `vm-iaN.duckdns.org`)

Le portail est alors sur `https://bureau.tondomaine.com/portal` — c'est cette
URL à partager désormais (fonctionne pour tout le monde, pas besoin d'IPv6).

## 5. Créer le compte Supabase partagé

Un seul compte suffit (email + mot de passe), à partager avec tes amis pour
passer la porte d'entrée du portail :
**Authentication > Users > Add user** dans Supabase, et désactive "Allow
new users to sign up" dans **Authentication > Settings**.
**Project Settings > API** : note le Project URL et la clé anon.

## 6. Déployer le portail

À la racine du repo (`~/AIpourletaff` sur le serveur), crée `.env.production` :

```bash
cat > ~/AIpourletaff/.env.production <<'EOF'
NEXT_PUBLIC_SUPABASE_URL=https://xxxxx.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=sb_publishable_xxxxx
ORCHESTRATOR_URL=http://127.0.0.1:8080
ORCHESTRATOR_SECRET=le-secret-affiche-par-setup-home-server.sh
EOF
```

Puis :

```bash
cd ~/AIpourletaff
./infra-home/deploy-portal.sh
```

Le portail est alors accessible sur `https://vm-ia1.duckdns.org/portal` —
c'est cette URL que tu partages avec tes amis (avec le login Supabase
partagé). Chacun choisit ensuite son propre trigramme dans le portail.

## Maintenance

- **Mettre à jour le portail après un changement de code** : `git pull` puis
  `./infra-home/deploy-portal.sh`
- **Voir l'état des slots** : `docker ps` (conteneurs "Up" = actifs) ou
  `curl -H "Authorization: Bearer <ORCH_SECRET>" http://127.0.0.1:8080/status`
- **Logs** : `sudo journalctl -u orchestrator -f`, `sudo journalctl -u portal -f`,
  `sudo journalctl -u caddy -f`
- **Voir les volumes de données par trigramme** : `docker volume ls | grep webtop-data-`
- **Changer le nombre de bureaux actifs simultanés autorisés** : éditer
  `MAX_CONCURRENT` dans `/etc/orchestrator.env` puis
  `sudo systemctl restart orchestrator`
- **Reconstruire l'image webtop+Firefox** (ex. après une mise à jour) :
  `sudo docker build -t webtop-firefox:local infra-home/docker` puis relancer
  `setup-home-server.sh`
