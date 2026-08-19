# Serveur maison multi-utilisateurs — guide pas-à-pas

Ce dossier configure le **serveur maison** (Ubuntu Server, `192.168.1.30`) qui fait
tourner un bureau distant Docker par ami, démarré à la demande. Il est
indépendant de `infra/` (qui reste pour la VM Google Cloud personnelle).

## 1. Créer les sous-domaines DuckDNS

Va sur [duckdns.org](https://www.duckdns.org), connecte-toi, et crée un
sous-domaine pour chaque slot **plus un** pour l'orchestrateur — avec un
préfixe de ton choix (ex. `qgo`), pour 10 slots :

```
qgo-u1 ... qgo-u10
qgo-orch
```

Laisse l'IP à blanc pour l'instant (`setup-home-server.sh` la mettra à jour
automatiquement via cron, ton IP domestique étant probablement dynamique).
Note ton **token DuckDNS** (visible en haut de la page une fois connecté).

## 2. Port-forward sur ta box

Dans l'admin de ta box (Freebox/Livebox/Bbox...), configure une redirection
des ports **80** et **443** vers l'IP locale du serveur (`192.168.1.30`).
La procédure exacte dépend du modèle — dis-le moi si tu bloques, je
t'accompagne.

## 3. Lancer le script sur le serveur

En SSH sur le serveur (`ssh -i ~/.ssh/home_server user1@192.168.1.30` depuis
ce PC) :

```bash
git clone https://github.com/QGO-SB/AIpourletaff.git
cd AIpourletaff/infra-home
chmod +x setup-home-server.sh set-slot-password.sh
sudo DUCKDNS_BASE=qgo DUCKDNS_TOKEN=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx ./setup-home-server.sh
```

Ça prend un moment (téléchargement de l'image webtop + install Firefox dans
chacun des 10 conteneurs). À la fin, le script affiche :
- Le secret de l'orchestrateur (`ORCHESTRATOR_SECRET`)
- L'URL de l'orchestrateur (`ORCHESTRATOR_URL`)
- L'emplacement du fichier des identifiants par slot (`/etc/slot-credentials.csv`)

## 4. Créer la table Supabase `profiles`

Dans le projet Supabase existant, **SQL Editor**, exécute :

```sql
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  slot int not null unique,
  domain text not null,
  basic_user text not null,
  basic_pass text not null,
  display_name text
);

alter table profiles enable row level security;

create policy "Users can read own profile"
  on profiles for select
  using (auth.uid() = id);
```

## 5. Ajouter chaque ami

Pour chaque personne :

1. **Authentication > Users > Add user** dans Supabase : crée son compte
   (email + mot de passe qu'elle utilisera pour se connecter au portail)
2. **Table Editor > profiles > Insert row** :
   - `id` : l'UUID du compte créé à l'étape précédente
   - `slot` : un numéro de 1 à 10, pas encore utilisé
   - `domain` : `qgo-u{slot}.duckdns.org`
   - `basic_user` / `basic_pass` : la ligne correspondante dans
     `/etc/slot-credentials.csv` sur le serveur (`cat /etc/slot-credentials.csv`)
   - `display_name` : son prénom, pour t'y retrouver

## 6. Configurer Vercel

Ajoute dans les variables d'environnement du projet Vercel :
- `ORCHESTRATOR_URL` = `https://qgo-orch.duckdns.org`
- `ORCHESTRATOR_SECRET` = le secret affiché à la fin du script

## Maintenance

- **Changer le mot de passe d'un ami** : `sudo ./set-slot-password.sh <slot>`
  sur le serveur, puis reporter le nouveau mot de passe affiché dans la
  colonne `basic_pass` de sa ligne Supabase.
- **Voir l'état des bureaux** : `docker ps` (conteneurs "Up" = actifs) ou
  `curl -H "Authorization: Bearer <ORCH_SECRET>" https://qgo-orch.duckdns.org/status`
- **Logs de l'orchestrateur** : `sudo journalctl -u orchestrator -f`
- **Changer le nombre de bureaux actifs simultanés autorisés** : éditer
  `MAX_CONCURRENT` dans `/etc/orchestrator.env` puis
  `sudo systemctl restart orchestrator`
