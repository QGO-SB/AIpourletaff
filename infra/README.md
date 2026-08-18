# Guide pas-à-pas — mise en place manuelle

Ces étapes sont à faire une seule fois, par toi (comptes tiers, paiement/carte
de vérification, DNS). Le code lui-même est déjà prêt dans ce repo.

## 1. Créer la VM Oracle Cloud (Always Free)

1. Crée un compte sur https://www.oracle.com/cloud/free/ (vérification carte
   requise par Oracle, mais aucun débit tant que tu restes sur les
   ressources "Always Free").
2. Console OCI > **Compute > Instances > Create Instance**.
   - Image : **Ubuntu 22.04**
   - Shape : **VM.Standard.A1.Flex** (Ampere ARM) — choisis 4 OCPU / 24 Go
     de RAM, gratuit en permanence dans la limite "Always Free".
   - Ajoute ta clé SSH publique (génère-en une avec `ssh-keygen` si besoin).
   - Réseau : garde le VCN par défaut, assure-toi qu'une **IP publique** est
     assignée.
3. Une fois créée, note l'**IP publique**.
4. Dans **Networking > Virtual Cloud Networks > (ton VCN) > Security Lists**,
   ajoute des règles d'entrée ("Ingress Rules") pour les ports **80** et
   **443** (source `0.0.0.0/0`, protocole TCP). C'est indispensable — sans
   ça, le firewall réseau d'Oracle bloque tout même si `setup-vm.sh` ouvre
   iptables localement.

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

```bash
ssh ubuntu@<IP-PUBLIQUE>
# copie infra/ sur la VM, par ex avec scp depuis ton PC :
#   scp -r infra ubuntu@<IP-PUBLIQUE>:~/infra
cd ~/infra
chmod +x setup-vm.sh
sudo DOMAIN=toinom.duckdns.org BASIC_USER=choisis-un-identifiant ./setup-vm.sh
```

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
  depuis la console OCI si tu ne l'utilises pas pendant longtemps (pas
  obligatoire en "Always Free", mais bonne pratique).
- Pour changer le mot de passe Basic Auth plus tard, relance
  `setup-vm.sh` avec un nouveau `BASIC_PASSWORD`, ou édite directement
  `/etc/caddy/Caddyfile` sur la VM puis `sudo systemctl reload caddy`.
