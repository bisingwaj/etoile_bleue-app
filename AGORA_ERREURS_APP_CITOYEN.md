# Codes d'erreur Agora RTC — Application Citoyen

Liste complète des erreurs que le SDK Agora RTC peut renvoyer à l'application citoyen, avec leurs cas de déclenchement et recommandations de gestion.

---

## 🔴 Erreurs de connexion au canal

| Code | Nom | Cas de déclenchement |
|------|-----|---------------------|
| **2** | `INVALID_PARAMS` | Paramètres invalides (token, channel name, uid mal formés) |
| **5** | `REFUSED` | Action refusée par le SDK (état incompatible, ex : rejoindre un canal déjà rejoint) |
| **17** | `JOIN_CHANNEL_REJECTED` | Rejoindre le canal refusé (déjà dans un autre canal) |
| **102** | `INVALID_CHANNEL_NAME` | Nom de canal invalide (caractères interdits, longueur > 64 caractères) |
| **109** | `TOKEN_EXPIRED` | Le token Agora a expiré (durée de vie dépassée) |
| **110** | `INVALID_TOKEN` | Token invalide (mauvais App ID, signature incorrecte, UID non concordant) |

---

## 🌐 Erreurs réseau

| Code | Nom | Cas de déclenchement |
|------|-----|---------------------|
| **4** | `NOT_SUPPORTED` | Navigateur ou device non supporté (iOS < 11, navigateur exotique) |
| **101** | `INVALID_APP_ID` | App ID Agora invalide ou non reconnu |
| — | `CAN_NOT_GET_GATEWAY_SERVER` | Impossible de joindre les serveurs Agora (DNS, firewall, pare-feu corporate) |
| — | `NETWORK_ERROR` | Connexion réseau perdue pendant l'appel |
| — | `NETWORK_TIMEOUT` | Timeout de connexion (réseau lent ou instable) |
| — | `WS_ABORT` | WebSocket fermé prématurément |
| — | `WS_DISCONNECT` | Déconnexion WebSocket inattendue |
| — | `WS_ERR` | Erreur générique WebSocket |

---

## 🎤 Erreurs micro / caméra (MediaDevices)

| Code | Nom | Cas de déclenchement |
|------|-----|---------------------|
| — | `PERMISSION_DENIED` (`NotAllowedError`) | L'utilisateur a refusé l'accès au micro/caméra |
| — | `DEVICE_NOT_FOUND` (`NotFoundError`) | Aucun micro ou caméra détecté sur l'appareil |
| — | `NOT_READABLE` (`NotReadableError`) | Le micro/caméra est utilisé par une autre application |
| — | `OVERCONSTRAINED` (`OverconstrainedError`) | Contraintes média impossibles à satisfaire (résolution non supportée) |
| — | `MEDIA_OPTION_INVALID` | Configuration média invalide (codec, bitrate) |
| — | `TRACK_IS_DISABLED` | Tentative d'utiliser une piste audio/vidéo désactivée |

---

## 📡 Erreurs de publication / souscription

| Code | Nom | Cas de déclenchement |
|------|-----|---------------------|
| — | `OPERATION_ABORTED` | Opération annulée (`leave()` pendant un `publish()`) |
| — | `PUBLISH_STREAM_FAILED` | Échec de publication du flux audio/vidéo |
| — | `SUBSCRIBE_FAILED` | Échec de souscription au flux d'un autre utilisateur |
| — | `UNPUBLISH_STREAM_FAILED` | Échec de dépublication |

---

## ⏱️ Erreurs de session

| Code | Nom | Cas de déclenchement |
|------|-----|---------------------|
| — | `CLIENT_IS_BANNED_BY_SERVER` | Utilisateur banni par le serveur (modération Agora) |
| — | `REMOTE_USER_IS_NOT_PUBLISHED` | Tentative de souscrire à un user qui ne publie pas |
| — | `UID_CONFLICT` | Deux clients tentent de rejoindre avec le même UID |
| — | `CHANNEL_NOT_EXIST` | Canal supprimé côté serveur |

---

## 🔁 Événements `connection-state-change`

États critiques à écouter (transitions, pas erreurs).

| État | Déclencheur |
|------|-------------|
| `DISCONNECTED` | Déconnexion volontaire ou erreur fatale |
| `CONNECTING` | Tentative initiale de connexion |
| `RECONNECTING` | Reconnexion automatique après perte réseau |
| `DISCONNECTING` | `leave()` en cours |

### Reasons associées (second paramètre de `connection-state-change`)

| Reason | Signification |
|--------|--------------|
| `LEAVE` | L'utilisateur a quitté volontairement |
| `NETWORK_ERROR` | Perte réseau |
| `SERVER_ERROR` | Erreur serveur Agora |
| `INTERRUPTED` | Interruption (appel téléphonique entrant côté OS) |
| `CHANNEL_BANNED` | Banni du canal |
| `IP_CHANGED` | Changement d'IP (Wi-Fi ↔ 4G) |
| `KEEP_ALIVE_TIMEOUT` | Heartbeat perdu |
| `UID_BANNED` | UID spécifique banni |

---

## 🚨 Cas particulièrement fréquents pour l'app citoyen

1. **`PERMISSION_DENIED`** → Le citoyen a refusé le micro lors du premier SOS → bloque l'appel.  
   **Action** : afficher un écran d'aide pour réactiver les permissions dans les paramètres système.

2. **`TOKEN_EXPIRED` (109)** → Token généré il y a plus d'1 h sans renouvellement.  
   **Action** : renouveler via l'edge function `agora-token` et appeler `client.renewToken(newToken)`.

3. **`NETWORK_ERROR` / `RECONNECTING`** → Réseau mobile RDC instable.  
   **Action** : afficher un indicateur visuel de reconnexion + bipper l'opérateur.

4. **`INTERRUPTED`** → Appel GSM entrant pendant un SOS VoIP.  
   **Action** : mettre en pause la piste audio puis reprendre automatiquement à la fin.

5. **`UID_CONFLICT`** → Le citoyen rouvre l'app alors que l'ancienne session existe encore.  
   **Action** : forcer `leave()` côté client avant tout nouveau `join()`.

6. **`CAN_NOT_GET_GATEWAY_SERVER`** → L'opérateur télécom bloque les ports UDP Agora.  
   **Action** : activer le fallback TCP via `AgoraRTC.setParameter("FORCE_TURN", true)`.

7. **`DEVICE_NOT_FOUND`** → Téléphone sans micro fonctionnel (rare mais possible).  
   **Action** : proposer un appel GSM classique en repli.

8. **`NOT_READABLE`** → Une autre app (WhatsApp, navigateur) occupe le micro.  
   **Action** : inviter l'utilisateur à fermer les autres apps.

---

## 📚 Référence officielle

- [Agora Web SDK NG Error Codes](https://api-ref.agora.io/en/voice-sdk/web/4.x/globals.html#agorartcerror)
- [Connection State Change Events](https://api-ref.agora.io/en/voice-sdk/web/4.x/interfaces/iagorartcclient.html#event_connection_state_change)
