# 📞 Documentation Technique : Intégration des Appels SOS (App Citoyen)

Ce document détaille le fonctionnement de l'intégration audio/vidéo entre l'application mobile citoyenne et le Dashboard Étoile Bleue. Il est destiné à l'équipe Backend/Dashboard pour assurer une synchronisation parfaite des états.

---

## 🏗️ Architecture Technique

- **Moteur Audio/Vidéo** : [Agora RTC](https://www.agora.io/en/).
- **Base de données & Temps Réel** : [Supabase](https://supabase.com/) (Table `call_history`, Realtime Postgres Changes).
- **Notifications Natives** : `CallKit` (iOS) et `Foreground Service` (Android).
- **Heartbeat (Battement de cœur)** : RPC PostgREST `citizen_call_heartbeat`.

---

## 1. Appel Sortant (SOS Citoyen) 🚨

C'est le scénario où le citoyen appuie sur le gros bouton SOS.

### Étape 1 : Création de l'Incident
L'application crée d'abord une ligne dans la table `incidents`.
- Elle génère une référence unique (ex: `SOS-1714000000000`).
- Elle récupère l'identifiant `incident_id`.

### Étape 2 : Initialisation de l'Appel (`call_history`)
L'application insère une ligne dans `call_history` :
- `channel_name` : La référence de l'incident (Invariant).
- `incident_id` : L'ID de l'incident créé.
- `citizen_id` : `auth.uid()`.
- `status` : `'ringing'`.
- `call_type` : `'audio'` (ou `'video'`).
- `started_at` : `now()`.

### Étape 3 : Heartbeat & Agora
- **Heartbeat** : L'application lance immédiatement un timer toutes les **10 secondes** appelant la RPC `citizen_call_heartbeat(p_channel_name)`.
- **Agora** : L'application rejoint le canal Agora (ID = `channel_name`).
- **Notification** : Sur Android, un "Foreground Service" affiche une notification persistante. Sur iOS, CallKit signale un appel sortant.

### Étape 4 : Attente & Décrochage
L'application écoute via **Realtime** les modifications de la ligne `call_history`.
- Quand l'opérateur "décroche" sur le dashboard, il passe le statut à `'active'`.
- L'application mobile détecte ce changement, arrête la tonalité de sonnerie et lance le chronomètre d'appel.

---

## 2. Appel Entrant (Opérateur -> Citoyen) 📞

C'est le scénario où un opérateur rappelle un citoyen depuis le dashboard.

### Étape 1 : Détection (Background/Foreground)
L'application écoute en permanence via **Supabase Realtime** les insertions dans `call_history` filtrées sur `citizen_id = auth.uid()`.
- Si `status == 'ringing'` ET `channel_name` ne commence PAS par `SOS-` ou `CALLBACK-`.

### Étape 2 : Signalement (CallKit / Notification)
- **Si l'app est en arrière-plan** : Déclenchement de **CallKit** (iOS) ou d'une notification plein écran (Android) via FCM ou Realtime.
- **Si l'app est au premier plan** : Affichage d'une interface d'appel entrant personnalisée.

### Étape 3 : Réponse (Answering)
Quand le citoyen appuie sur "Répondre" :
- L'application rejoint le canal Agora indiqué dans `channel_name`.
- **Action Dashboard** : Le dashboard détecte la réponse via le heartbeat citoyen et/ou l'opérateur décroche. **Le mobile ne doit jamais forcer le statut à `active`**.
- L'application lance le **Heartbeat** obligatoire toutes les 10s.

### Étape 4 : Refus (Declining)
Quand le citoyen appuie sur "Décliner" :
- L'application met à jour `call_history` : `status = 'completed'`, `ended_by = 'citizen_rejected'`, `ended_at = now()`.
- L'interface se ferme immédiatement.

---

## 3. Gestion de la Fin d'Appel (Raccrochage) 🔚

Le protocole de raccrochage est critique pour éviter les "appels fantômes".

### Cas A : Le Citoyen raccroche
1. **UPDATE DB** : L'application met à jour la ligne `call_history` :
   - `status = 'completed'`
   - `ended_by = 'citizen'`
   - `ended_at = now()`
   - *Filtre de sécurité* : `.not('status', 'in', ['completed', 'missed', 'failed'])`.
2. **Agora** : Appel à `leaveChannel()`.
3. **Nettoyage** : Arrêt du Heartbeat, arrêt du Foreground Service, arrêt du Wakelock.

### Cas B : L'Opérateur raccroche (ou erreur serveur)
L'application écoute via **Realtime** les mises à jour de `call_history`.
- Si `status` passe à un état terminal (`completed`, `missed`, `failed`) ET `ended_by != 'citizen'`.
1. **Action Mobile** : L'application affiche "Appel terminé par l'opérateur".
2. **Nettoyage** : Libération immédiate des ressources Agora et fermeture de l'interface.

---

## 4. Nettoyage & Sécurité (Filets de sécurité) 🛡️

### Heartbeat (RPC `citizen_call_heartbeat`)
L'application appelle cette fonction toutes les **10 secondes** tant que le citoyen est dans l'écran d'appel (ringing ou active).
- Si le heartbeat s'arrête (crash app, perte réseau totale) :
  - Le Watchdog serveur ferme l'appel après **60s** (si ringing) ou **90s** (si active).

### Orphan Recovery (Récupération au démarrage)
À chaque lancement ou reconnexion de l'application :
- L'application cherche des lignes `call_history` en statut `ringing` ou `active` appartenant au citoyen qui auraient plus de 30s.
- Elle les ferme proprement avec `ended_by = 'citizen_recovery'`.

---

## 5. Résumé des États (`status`)

| État | Origine | Signification |
|---|---|---|
| `ringing` | Citoyen ou Opérateur | L'appel est initié, l'autre partie sonne. |
| `active` | **Dashboard uniquement** | La connexion audio/vidéo est établie. |
| `completed` | Citoyen/Opérateur | L'appel s'est terminé (hangup, rejet ou recovery). |
| `missed` | Serveur (Watchdog) | L'appel a expiré sans réponse (ringing > 60s). |
| `failed` | Serveur (Watchdog) | Erreur technique détectée par le serveur. |

⚠️ Note : `abandoned` existe uniquement sur la table **`call_queue`**, **PAS** sur `call_history`. Ne pas confondre.

---

## 📝 Notes pour Lovable (Équipe Backend/React)

1.  **Invariant `channel_name`** : Toujours utiliser la `reference` de l'incident comme nom de canal Agora.
2.  **RPC Heartbeat** : Assurez-vous que la fonction `citizen_call_heartbeat` est bien déployée et qu'elle met à jour `updated_at`.
3.  **Realtime** : L'application citoyenne dépend fortement du Realtime sur la table `call_history` pour fermer l'UI quand l'opérateur raccroche.
4.  **Transitions** : Ne pas hésiter à utiliser le statut `active` pour synchroniser le début réel de la conversation.
