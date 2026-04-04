# Prompt Cursor — Système de Blocage Utilisateur (Application Citoyenne Flutter)

## Contexte

L'application web du centre d'appels d'urgence (Étoile Bleue) dispose désormais d'un système de **liste noire** permettant aux opérateurs de bloquer temporairement des citoyens qui abusent du système SOS. Côté backend (Supabase), une table `blocked_users` et une fonction RPC `is_citizen_blocked` sont déjà en place.

**Tu dois implémenter côté Flutter l'interception des appels SOS pour les utilisateurs bloqués.**

---

## Architecture Backend (déjà en place)

### Table `blocked_users`

```sql
CREATE TABLE public.blocked_users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  citizen_id uuid NOT NULL,        -- auth.users.id du citoyen bloqué
  blocked_by uuid NOT NULL,        -- ID de l'opérateur qui a bloqué
  reason text NOT NULL DEFAULT '',
  duration_hours integer NOT NULL DEFAULT 168,
  blocked_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,  -- Date/heure d'expiration du blocage
  is_active boolean NOT NULL DEFAULT true,
  call_id uuid,
  incident_id uuid,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);
```

### Fonction RPC `is_citizen_blocked`

```dart
// Appel depuis Flutter :
final response = await supabase.rpc('is_citizen_blocked', params: {
  'p_citizen_id': supabase.auth.currentUser!.id,
});
// Réponse : { "blocked": true, "expires_at": "2026-04-07T12:00:00Z", "reason": "...", "blocked_at": "..." }
// Ou :      { "blocked": false }
```

---

## Ce que tu dois implémenter

### 1. Intercepter AVANT tout appel SOS

Dans le service d'urgence (`emergency_call_service.dart` ou équivalent), **avant** de :
- Créer un incident dans la table `incidents`
- Générer un token Agora
- Rejoindre un canal Agora

Tu dois appeler `is_citizen_blocked` :

```dart
Future<Map<String, dynamic>> checkBlocked() async {
  final user = supabase.auth.currentUser;
  if (user == null) return {'blocked': false};
  
  final result = await supabase.rpc('is_citizen_blocked', params: {
    'p_citizen_id': user.id,
  });
  
  return Map<String, dynamic>.from(result as Map);
}
```

Si `result['blocked'] == true` → **ne pas lancer l'appel**, afficher l'écran de blocage.

### 2. Écran de Blocage — Design WhatsApp-like

Crée un écran `BlockedScreen` ou `SuspendedScreen` avec le design suivant :

#### Structure visuelle (style WhatsApp / application moderne)

```
┌──────────────────────────────────────┐
│                                      │
│         🛡️ (Icône animée)           │
│                                      │
│    Compte temporairement suspendu    │
│                                      │
│  ┌────────────────────────────────┐  │
│  │  Votre accès au service SOS    │  │
│  │  est temporairement suspendu   │  │
│  │  suite à une activité          │  │
│  │  inhabituelle détectée sur     │  │
│  │  votre compte.                 │  │
│  └────────────────────────────────┘  │
│                                      │
│  ⏱️ Suspension levée dans :         │
│                                      │
│     ┌──┐  ┌──┐  ┌──┐  ┌──┐        │
│     │2 │: │14│: │37│: │05│        │
│     │J │  │H │  │M │  │S │        │
│     └──┘  └──┘  └──┘  └──┘        │
│                                      │
│  ┌────────────────────────────────┐  │
│  │  ⚠️ Pourquoi cette mesure ?    │  │
│  │                                │  │
│  │  Les appels abusifs empêchent  │  │
│  │  les personnes en réelle       │  │
│  │  détresse d'accéder à l'aide   │  │
│  │  dont elles ont besoin.        │  │
│  │                                │  │
│  │  Chaque faux appel mobilise    │  │
│  │  des ressources qui pourraient │  │
│  │  sauver des vies.              │  │
│  └────────────────────────────────┘  │
│                                      │
│  Si vous pensez qu'il s'agit d'une  │
│  erreur, contactez le support :      │
│  📞 +243 XX XXX XXXX               │
│                                      │
└──────────────────────────────────────┘
```

#### Spécifications de design

- **Fond** : Gradient subtil (gris clair vers blanc, ou couleur de marque atténuée)
- **Icône** : Bouclier avec animation de pulsation douce (pas agressif)
- **Titre** : Gras, taille 22-24sp, couleur sombre
- **Message principal** : Dans un card arrondi, fond légèrement coloré
- **Compte à rebours** : 
  - Composants individuels pour Jours/Heures/Minutes/Secondes
  - Fond coloré (bleu/gris foncé), texte blanc, coins arrondis
  - Se met à jour en temps réel chaque seconde
  - Calculé dynamiquement depuis `expires_at`
- **Section "Pourquoi"** : Card avec icône ⚠️, texte empathique mais ferme
- **Contact support** : Lien cliquable vers le numéro de support
- **PAS de bouton d'action** : L'utilisateur ne peut rien faire, juste attendre

#### Code Flutter (structure de base)

```dart
class BlockedScreen extends StatefulWidget {
  final DateTime expiresAt;
  final String reason;
  
  const BlockedScreen({
    required this.expiresAt,
    required this.reason,
    super.key,
  });

  @override
  State<BlockedScreen> createState() => _BlockedScreenState();
}

class _BlockedScreenState extends State<BlockedScreen> {
  late Timer _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateRemaining());
  }

  void _updateRemaining() {
    final now = DateTime.now();
    setState(() {
      _remaining = widget.expiresAt.difference(now);
      if (_remaining.isNegative) {
        _remaining = Duration.zero;
        _timer.cancel();
        // Revérifier le statut et naviguer si débloqué
        _checkAndRedirect();
      }
    });
  }

  Future<void> _checkAndRedirect() async {
    final result = await supabase.rpc('is_citizen_blocked', params: {
      'p_citizen_id': supabase.auth.currentUser!.id,
    });
    if (result['blocked'] == false && mounted) {
      Navigator.of(context).pop(); // Retour à l'écran principal
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final days = _remaining.inDays;
    final hours = _remaining.inHours % 24;
    final minutes = _remaining.inMinutes % 60;
    final seconds = _remaining.inSeconds % 60;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icône animée
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.8, end: 1.0),
                  duration: const Duration(seconds: 2),
                  curve: Curves.easeInOut,
                  builder: (_, value, child) => Transform.scale(scale: value, child: child),
                  child: Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.shield, size: 40, color: Colors.red),
                  ),
                ),
                const SizedBox(height: 24),
                
                // Titre
                const Text(
                  'Compte temporairement suspendu',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                
                // Message principal
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.orange.withOpacity(0.2)),
                  ),
                  child: const Text(
                    'Votre accès au service SOS est temporairement suspendu suite à une activité inhabituelle détectée sur votre compte.',
                    style: TextStyle(fontSize: 15, height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 32),
                
                // Compte à rebours
                const Text('Suspension levée dans :', style: TextStyle(fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildTimeUnit(days.toString().padLeft(2, '0'), 'J'),
                    const Text(' : ', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    _buildTimeUnit(hours.toString().padLeft(2, '0'), 'H'),
                    const Text(' : ', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    _buildTimeUnit(minutes.toString().padLeft(2, '0'), 'M'),
                    const Text(' : ', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    _buildTimeUnit(seconds.toString().padLeft(2, '0'), 'S'),
                  ],
                ),
                const SizedBox(height: 32),
                
                // Section explicative
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_amber, color: Colors.orange[700], size: 20),
                          const SizedBox(width: 8),
                          Text('Pourquoi cette mesure ?',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[700])),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Les appels abusifs empêchent les personnes en réelle détresse d\'accéder à l\'aide dont elles ont besoin.\n\n'
                        'Chaque faux appel mobilise des ressources qui pourraient sauver des vies.',
                        style: TextStyle(fontSize: 14, height: 1.5, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                // Contact support
                Text(
                  'Si vous pensez qu\'il s\'agit d\'une erreur, contactez le support :',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () {
                    // Ouvrir le dialer avec le numéro de support
                    // launchUrl(Uri.parse('tel:+243XXXXXXXXX'));
                  },
                  child: const Text(
                    '📞 +243 XX XXX XXXX',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.blue),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeUnit(String value, String label) {
    return Column(
      children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFF1E3A5F),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(value, style: const TextStyle(
            fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white,
          )),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}
```

### 3. Intégration dans le flux SOS

Dans ton service d'appel d'urgence, **avant** `createIncident()` et `joinAgoraChannel()` :

```dart
// Dans emergency_call_service.dart ou sos_provider.dart

Future<void> triggerSOS() async {
  // 1. Vérifier le blocage AVANT tout
  final blockStatus = await checkBlocked();
  
  if (blockStatus['blocked'] == true) {
    final expiresAt = DateTime.parse(blockStatus['expires_at']);
    final reason = blockStatus['reason'] ?? '';
    
    // Naviguer vers l'écran de blocage
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BlockedScreen(
          expiresAt: expiresAt,
          reason: reason,
        ),
      ),
    );
    return; // STOP — ne pas créer d'incident ni rejoindre Agora
  }

  // 2. Si non bloqué, continuer le flux normal
  await createIncident();
  await joinAgoraChannel();
  // ...
}
```

### 4. Points critiques

1. **L'appel RPC `is_citizen_blocked` doit être fait AVANT la création d'incident** — sinon l'appel arrivera quand même au centre
2. **Le `citizen_id` utilisé est `supabase.auth.currentUser!.id`** (UUID de `auth.users`, pas l'ID de `users_directory`)
3. **Le compte à rebours doit être dynamique** — calculé depuis `expires_at` retourné par le RPC
4. **Quand le timer atteint 0**, revérifier automatiquement via RPC et rediriger si débloqué
5. **Aucun bouton d'action sur l'écran** — l'utilisateur ne peut que attendre ou contacter le support par téléphone classique
6. **Le numéro de support** doit être configurable (constante ou remote config)

### 5. Tests à faire

- [ ] Bloquer un utilisateur depuis le dashboard web (Liste noire → Bloquer → 24h)
- [ ] Lancer un SOS depuis l'app mobile avec le même compte → doit afficher l'écran de blocage
- [ ] Vérifier que le compte à rebours décompte en temps réel
- [ ] Attendre l'expiration (ou débloquer depuis le dashboard) → vérifier que l'app redirige automatiquement
- [ ] Vérifier qu'aucun incident n'est créé, aucun canal Agora rejoint quand l'utilisateur est bloqué

---

## Résumé des fichiers à modifier/créer

| Fichier | Action |
|---|---|
| `lib/screens/blocked_screen.dart` | **Créer** — Écran de suspension avec countdown |
| `lib/services/emergency_call_service.dart` | **Modifier** — Ajouter vérification `is_citizen_blocked` avant SOS |
| `lib/providers/sos_provider.dart` (si existant) | **Modifier** — Intercepter avant création d'incident |

## Variables Supabase

L'app doit déjà avoir les variables Supabase configurées. La fonction RPC `is_citizen_blocked` est accessible via `supabase.rpc()` avec l'anon key standard — pas besoin de service role key côté mobile.

---

## Protection serveur (déjà en place)

**Important** : Le trigger PostgreSQL `on_incident_created` a été mis à jour pour vérifier automatiquement le statut de blocage côté serveur. Même si l'application mobile échoue à vérifier le blocage (crash, version ancienne, etc.), le backend :

1. Vérifie `is_citizen_blocked(citizen_id)` avant de mettre l'appel en file d'attente
2. Si bloqué : l'incident est automatiquement marqué `status = 'ended'`, `ended_by = 'system_blocked'`
3. Aucune entrée `call_queue` n'est créée → aucun opérateur n'est dérangé

C'est un filet de sécurité double : la vérification côté mobile offre une bonne UX (écran de blocage instantané), et la vérification côté serveur assure qu'aucun appel bloqué n'atteint jamais le centre d'appels.
