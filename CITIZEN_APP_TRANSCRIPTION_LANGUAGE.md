# Citizen App — Hint de langue pour la transcription temps réel

> **Public visé :** équipe mobile Flutter de l'application citoyen.
> **Impact côté serveur :** purement additif. Aucune signalisation, aucun flux Agora, aucun verrouillage d'appel n'est modifié.
> **Statut :** déjà livré côté plateforme web. La colonne `caller_preferred_language` existe en base et est lue par le moteur de transcription multilingue.

---

## 1. Objectif

La centrale d'urgence transcrit désormais chaque appel **en temps réel** avec **détection automatique de la langue** (FR · LN · SW · EN). Pour accélérer la détection sur les premières secondes (en particulier pour le **Lingala** qui n'est pas natif dans Scribe v2), l'application citoyen peut **déclarer la langue préférée** du citoyen au moment où elle insère l'appel dans `call_history`.

Si vous n'envoyez rien, **rien ne casse** : la centrale tombe en mode détection 100 % automatique. Le hint sert uniquement à raccourcir la latence du premier mot transcrit.

---

## 2. Contrat technique

### 2.1 Champ à ajouter

| Table | Colonne | Type | Nullable | Valeurs ISO 639-3 |
|---|---|---|---|---|
| `public.call_history` | `caller_preferred_language` | `text` | ✅ oui | `fra` · `lin` · `swa` · `eng` |

La migration est **déjà passée** côté Lovable Cloud — vous n'avez rien à faire en base.

### 2.2 Quand renseigner

À l'instant où l'appli mobile crée la ligne `call_history` (au moment du démarrage de l'appel SOS, **avant** publication du flux Agora). Si vous mettez à jour la ligne plus tard, la valeur sera ignorée par la transcription (elle ne lit la colonne qu'au moment de la prise d'appel par l'opérateur).

### 2.3 Détermination de la langue

Ordre de priorité recommandé :
1. **Préférence utilisateur enregistrée** dans le profil citoyen (`profiles.preferred_language`, déjà persistée à l'inscription).
2. **Locale système** Flutter via `Platform.localeName` (mappée en ISO 639-3).
3. **Aucune valeur** envoyée → fallback détection auto côté centrale.

### 2.4 Mapping Flutter → ISO 639-3

```dart
String? toIso6393(String? localeOrPref) {
  if (localeOrPref == null) return null;
  final raw = localeOrPref.toLowerCase();
  // Préférences explicites de l'app
  if (raw == 'lingala' || raw.startsWith('ln')) return 'lin';
  if (raw == 'swahili' || raw.startsWith('sw')) return 'swa';
  if (raw == 'english' || raw.startsWith('en')) return 'eng';
  if (raw == 'francais' || raw == 'français' || raw.startsWith('fr')) return 'fra';
  return null;
}
```

---

## 3. Snippet Flutter copy-paste

À placer dans le service qui insère la ligne `call_history` (ex. `lib/services/sos_call_service.dart`).

```dart
import 'dart:io' show Platform;
import 'package:supabase_flutter/supabase_flutter.dart';

Future<String> startSosCall({
  required String channelName,
  required String citizenId,
  String? preferredLanguageOverride,
}) async {
  final client = Supabase.instance.client;

  // 1. Préférence explicite > profil > locale système > null
  final profileLang = await client
      .from('profiles')
      .select('preferred_language')
      .eq('user_id', citizenId)
      .maybeSingle();

  final hint = toIso6393(
    preferredLanguageOverride
      ?? profileLang?['preferred_language'] as String?
      ?? Platform.localeName,
  );

  // 2. INSERT call_history avec la colonne caller_preferred_language
  final inserted = await client.from('call_history').insert({
    'channel_name': channelName,
    'citizen_id': citizenId,
    'call_type': 'sos',
    'status': 'ringing',
    'caller_preferred_language': hint,                 // 👈 nouveau champ (nullable)
    // ... autres champs déjà envoyés (caller_phone, caller_lat/lng, etc.)
  }).select('id').single();

  return inserted['id'] as String;
}
```

> ⚠️ **Ne pas appeler `update()` après coup pour modifier `caller_preferred_language`** — la valeur n'est lue qu'à la prise d'appel.

---

## 4. QA checklist

| Cas | Action | Résultat attendu côté centrale |
|---|---|---|
| **FR** | Citoyen avec `preferred_language: 'francais'` lance un SOS et parle français | Transcription instantanée, badge `FR` sur chaque ligne |
| **LN** | Citoyen avec `preferred_language: 'lingala'` lance un SOS et parle lingala | Premier segment apparaît en ≤ 800 ms, badge `LN` (rendu via moteur swahili) |
| **SW** | Citoyen avec `preferred_language: 'swahili'` lance un SOS et parle kiswahili | Transcription correcte, badge `SW` |
| **Sans hint** | Citoyen sans `preferred_language`, parle français puis bascule en lingala | Premier mot ≤ 1.5 s en `FR`, basculement automatique sur `LN` après ~1 segment |

---

## 5. Garanties

- Champ **optionnel** : si vous n'envoyez rien, le mode détection auto fait le boulot.
- **Aucune régression Agora** : le flux audio reste identique, même `appId`, même channel.
- **Aucun changement de signalisation push** : `send-call-push` continue de fonctionner sans modification.
- **Aucun changement de schéma destructif** : la colonne est nullable, default NULL.

---

## 6. Contact

Toute question ou divergence remontée par le QA → ping centrale via le canal `#urgences-tech`.
