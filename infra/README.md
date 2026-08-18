# Guide pas-à-pas — mise en place manuelle

Ces étapes sont à faire une seule fois, par toi (comptes tiers, paiement/carte
de vérification, DNS). Le code lui-même est déjà prêt dans ce repo.

## 1. Créer la VM Google Cloud (Always Free)

Basculé depuis Oracle Cloud suite à des ruptures de capacité répétées sur
les shapes gratuits (Ampere A1 et E2.1.Micro) en région Paris. Google Cloud
propose un shape **e2-micro gratuit à vie** (pas un essai limité dans le
temps), avec une bien meilleure disponibilité — seul compromis : uniquement
dans 3 régions US (`us-west1`, `us-central1`, `us-east1`), donc un peu plus
de latence depuis la France.

1. Crée un compte sur https://console.cloud.google.com (carte de
   vérification requise par Google, aucun débit tant que tu restes sur les
   ressources "Always Free" et hors essai gratuit initial de 90 jours/300$
   qu'il vaut mieux ne pas activer ou surveiller pour ne pas en sortir par
   erreur).
2. Crée un projet (menu du haut > "New Project").
3. **Compute Engine > VM instances > Create Instance**.
   - Région : **us-central1** (Iowa) — bonne dispo, bon compromis latence
   - Machine type : **e2-micro** (2 vCPU partagés / 1 Go RAM, "Free tier
     eligible" affiché à côté)
   - Boot disk : **Ubuntu 24.04 LTS**, 30 Go standard persistent disk max
     (inclus dans le free tier)
   - Firewall : coche **Allow HTTP traffic** et **Allow HTTPS traffic**
   - Pas besoin d'ajouter de clé SSH manuellement : la connexion se fait
     directement depuis la console (bouton **SSH**), authentifiée par ton
     compte Google.
4. Clique **Create**. Une fois l'instance "Running", note son **IP externe**
   (colonne "External IP" dans la liste des instances).
5. Si tu veux resserrer l'accès réseau : **VPC network > Firewall**, vérifie
   qu'il existe bien des règles autorisant les ports **80** et **443** en
   entrée (`0.0.0.0/0`, TCP) — normalement créées automatiquement par les
   cases cochées à l'étape 3.

## 2. DNS gratuit (DuckDNS)

1. Va sur https://www.duckdns.org, connecte-toi (GitHub/Google...).
2. Crée un sous-domaine, ex. `toinom.duckdns.org`, et pointe-le vers l'IP
   publique notée à l'étape 1.
3. (Optionnel mais recommandé) installe le petit script de mise à jour
   DuckDNS en cron sur la VM si tu utilises une IP publique **éphémère**
   (le tier "Always Free" permet normalement de réserver une IP publique
   fixe — préfère cette option pour éviter d'avoir à gérer une mise à jour
   DNS automatique).

## 3. Configurer la VM

1. Dans **Compute Engine > VM instances**, clique le bouton **SSH** à côté
   de ton instance : ça ouvre un terminal directement dans le navigateur,
   pas besoin de clé SSH ni de logiciel local.
2. Récupère le script directement depuis GitHub (le repo ne contient aucun
   secret — les vrais identifiants restent dans `.env.local`, jamais
   commités) :

```bash
git clone https://github.com/QGO-SB/AIpourletaff.git
cd AIpourletaff/infra
chmod +x setup-vm.sh
sudo DOMAIN=toinom.duckdns.org BASIC_USER=choisis-un-identifiant ./setup-vm.sh
```

Si le `git clone` échoue avec une erreur d'accès (repo privé), rends
temporairement le repo public sur GitHub (**Settings > General > Danger
Zone > Change visibility**) le temps du clone, ou repasse-le en privé après
— aucun secret n'y est stocké donc ce n'est pas un risque en soi.

Le script demande un mot de passe VNC (accès local) puis un mot de passe
Basic Auth (celui qui protège l'accès web) — retiens ce dernier, c'est celui
que tu mettras dans `VM_BASIC_AUTH_PASS` sur Vercel.

Une fois terminé, teste dans un navigateur : `https://toinom.duckdns.org`
(le navigateur doit demander les identifiants Basic Auth, puis afficher le
bureau Xfce).

## 4. Créer le projet Supabase

1. https://supabase.com > New project (free tier).
2. **Authentication > Providers > Email** : laisse activé.
3. **Authentication > Settings** : désactive "Enable email signups" une fois
   que tu as créé ton propre utilisateur (ou laisse activé mais crée-toi
   directement un compte via **Authentication > Users > Add user**) — le
   but est qu'aucun visiteur externe ne puisse s'auto-inscrire.
4. **Project Settings > API** : note `Project URL` et `anon public key`.

## 5. Créer le repo GitHub et pousser le code

```bash
git init
git add .
git commit -m "Initial commit"
gh repo create appli-bureau-ia --private --source=. --push
```

(ou crée le repo sur github.com puis `git remote add origin ...` + `git push`)

## 6. Déployer sur Vercel

1. https://vercel.com > **Add New > Project** > importe le repo GitHub.
2. Dans **Environment Variables**, ajoute :
   - `NEXT_PUBLIC_SUPABASE_URL`
   - `NEXT_PUBLIC_SUPABASE_ANON_KEY`
   - `VM_URL` = `https://toinom.duckdns.org`
   - `VM_BASIC_AUTH_USER`
   - `VM_BASIC_AUTH_PASS`
3. Déploie. Chaque `git push` redéploiera automatiquement.

## Maintenance

- Le bureau distant ne s'arrête jamais tout seul : pense à couper la VM
  depuis la console Google Cloud si tu ne l'utilises pas pendant longtemps
  (pas obligatoire en "Always Free", mais bonne pratique).
- Pour changer le mot de passe Basic Auth plus tard, relance
  `setup-vm.sh` avec un nouveau `BASIC_PASSWORD`, ou édite directement
  `/etc/caddy/Caddyfile` sur la VM puis `sudo systemctl reload caddy`.
