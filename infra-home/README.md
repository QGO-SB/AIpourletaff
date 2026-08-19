# Serveur maison multi-utilisateurs — guide pas-à-pas

Ce dossier configure le **serveur maison** (Ubuntu Server, `192.168.1.30`) qui fait
tourner un bureau distant Docker par personne, démarré à la demande. Il est
indépendant de `infra/` (qui reste pour la VM Google Cloud personnelle).

**Modèle** : un seul login Supabase partagé donne accès au portail. Une fois
connecté, chacun tape un **trigramme** libre (ex. "QGO") pour s'identifier —
son bureau et ses données (profil Firefox, historique, comptes connectés)
sont automatiquement créés au premier usage et le suivent d'une session à
l'autre, peu importe le slot physique attribué. Rien à enregistrer à l'avance.

## 1. Créer les sous-domaines DuckDNS

Va sur [duckdns.org](https://www.duckdns.org), connecte-toi, et crée un
sous-domaine par slot **plus un** pour l'orchestrateur — avec le préfixe de
ton choix (ex. `vm-ia`), pour 10 slots :

```
vm-ia1 ... vm-ia10
vm-ia-orch
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
sudo DUCKDNS_PREFIX=vm-ia DUCKDNS_TOKEN=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx ./setup-home-server.sh
```

Ça prend un moment (construction de l'image Docker webtop + Firefox). À la
fin, le script affiche :
- Le secret de l'orchestrateur (`ORCHESTRATOR_SECRET`)
- L'URL de l'orchestrateur (`ORCHESTRATOR_URL`)

## 4. Configurer Vercel

Ajoute dans les variables d'environnement du projet Vercel :
- `ORCHESTRATOR_URL` = `https://vm-ia-orch.duckdns.org`
- `ORCHESTRATOR_SECRET` = le secret affiché à la fin du script

## 5. Créer le compte Supabase partagé

Un seul compte suffit (email + mot de passe), à partager avec tes amis pour
passer la porte d'entrée du portail :
**Authentication > Users > Add user** dans Supabase, et désactive "Allow
new users to sign up" dans **Authentication > Settings**.

C'est tout — chacun choisit ensuite son propre trigramme dans le portail.

## Maintenance

- **Changer le mot de passe Basic Auth d'un slot** : `sudo ./set-slot-password.sh <slot>`
  sur le serveur (les identifiants sont valables pour n'importe quel
  trigramme qui atterrit sur ce slot, ce n'est pas personnel).
- **Voir l'état des slots** : `docker ps` (conteneurs "Up" = actifs) ou
  `curl -H "Authorization: Bearer <ORCH_SECRET>" https://vm-ia-orch.duckdns.org/status`
- **Logs de l'orchestrateur** : `sudo journalctl -u orchestrator -f`
- **Voir les volumes de données par trigramme** : `docker volume ls | grep webtop-data-`
- **Changer le nombre de bureaux actifs simultanés autorisés** : éditer
  `MAX_CONCURRENT` dans `/etc/orchestrator.env` puis
  `sudo systemctl restart orchestrator`
- **Reconstruire l'image webtop+Firefox** (ex. après une mise à jour) :
  `sudo docker build -t webtop-firefox:local infra-home/docker` puis relancer
  `setup-home-server.sh`
