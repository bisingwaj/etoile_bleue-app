# Prompt Cursor — Questionnaire SOS Dynamique (Flutter)

## Contexte

L'application mobile Flutter doit afficher un questionnaire SOS dynamique dont les questions sont configurées en temps réel depuis le dashboard web. Les questions sont stockées dans la table Supabase `sos_questions` et synchronisées via Realtime.

---

## 1. Schéma de la table `sos_questions`

```sql
id              uuid PRIMARY KEY
question_key    text UNIQUE NOT NULL       -- ex: "victime_consciente"
question_text   text NOT NULL              -- texte FR par défaut
question_type   text DEFAULT 'single_choice' -- single_choice | multiple_choice | boolean | text
options         jsonb DEFAULT '[]'         -- [{"label": "Oui", "weight": 3}, {"label": "Non", "weight": 0}]
display_order   integer DEFAULT 0
is_active       boolean DEFAULT true
is_required     boolean DEFAULT false
category        text DEFAULT 'triage'
template        text DEFAULT 'default'     -- default | medical | incendie | agression | accident
parent_question_key text NULL              -- clé de la question parente (logique conditionnelle)
show_if_answer  jsonb NULL                 -- ["Incendie", "Accident"] — afficher si réponse parente dans cette liste
translations    jsonb DEFAULT '{}'         -- traductions multilingues
created_at      timestamptz
updated_at      timestamptz
```

### Structure `translations`

```json
{
  "en": {
    "text": "Is the victim conscious?",
    "options": ["Yes", "No"]
  },
  "ln": {
    "text": "Moto azali na makanisi?",
    "options": ["Iyo", "Te"]
  },
  "sw": {
    "text": "Mwathirika ana fahamu?",
    "options": ["Ndiyo", "Hapana"]
  }
}
```

- `translations[lang].options[i]` correspond à `options[i].label` (même index)
- Le français (FR) est le texte par défaut dans `question_text` et `options[].label`

---

## 2. Modèle Dart

```dart
class SOSQuestionOption {
  final String label;
  final int weight;
  SOSQuestionOption({required this.label, required this.weight});
  
  factory SOSQuestionOption.fromJson(Map<String, dynamic> json) => SOSQuestionOption(
    label: json['label'] ?? '',
    weight: json['weight'] ?? 0,
  );
}

class SOSQuestionTranslation {
  final String text;
  final List<String> options;
  SOSQuestionTranslation({required this.text, required this.options});
  
  factory SOSQuestionTranslation.fromJson(Map<String, dynamic> json) => SOSQuestionTranslation(
    text: json['text'] ?? '',
    options: List<String>.from(json['options'] ?? []),
  );
}

class SOSQuestion {
  final String id;
  final String questionKey;
  final String questionText;       // texte FR par défaut
  final String questionType;
  final List<SOSQuestionOption> options;
  final int displayOrder;
  final bool isActive;
  final bool isRequired;
  final String category;
  final String template;
  final String? parentQuestionKey;
  final List<String>? showIfAnswer;
  final Map<String, SOSQuestionTranslation> translations;
  final DateTime updatedAt;

  SOSQuestion({...});

  /// Retourne le texte traduit avec fallback FR
  String getLocalizedText(String lang) {
    if (lang == 'fr') return questionText;
    return translations[lang]?.text ?? questionText;
  }

  /// Retourne le label de l'option traduit avec fallback FR
  String getLocalizedOption(int index, String lang) {
    if (lang == 'fr') return options[index].label;
    final translated = translations[lang]?.options;
    if (translated != null && index < translated.length && translated[index].isNotEmpty) {
      return translated[index];
    }
    return options[index].label;
  }
}
```

---

## 3. Sélecteur de langue — Premier écran

Avant d'afficher les questions SOS, présenter un écran de sélection de langue :

```dart
class LanguageSelectionScreen extends StatelessWidget {
  final Function(String langCode) onLanguageSelected;

  static const supportedLanguages = [
    {'code': 'fr', 'label': 'Français', 'flag': '🇫🇷'},
    {'code': 'en', 'label': 'English', 'flag': '🇬🇧'},
    {'code': 'ln', 'label': 'Lingala', 'flag': '🇨🇩'},
    {'code': 'sw', 'label': 'Kiswahili', 'flag': '🇹🇿'},
    {'code': 'ts', 'label': 'Tshiluba', 'flag': '🇨🇩'},
    {'code': 'kg', 'label': 'Kikongo', 'flag': '🇨🇩'},
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Choisissez votre langue / Choose your language'),
        SizedBox(height: 24),
        ...supportedLanguages.map((lang) => ElevatedButton(
          onPressed: () => onLanguageSelected(lang['code']!),
          child: Row(children: [
            Text(lang['flag']!, style: TextStyle(fontSize: 24)),
            SizedBox(width: 12),
            Text(lang['label']!),
          ]),
        )),
      ],
    );
  }
}
```

La langue choisie est passée au provider SOS pour filtrer l'affichage.

---

## 4. Stratégie de cache et synchronisation

### 4.1 Cache local (SharedPreferences / Hive)

```dart
class SOSQuestionsCache {
  static const _cacheKey = 'sos_questions_cache';
  static const _lastSyncKey = 'sos_questions_last_sync';

  /// Charge les questions depuis le cache local
  static Future<List<SOSQuestion>?> loadFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);
    if (cached == null) return null;
    final list = jsonDecode(cached) as List;
    return list.map((e) => SOSQuestion.fromJson(e)).toList();
  }

  /// Sauvegarde les questions en cache
  static Future<void> saveToCache(List<SOSQuestion> questions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(questions.map((q) => q.toJson()).toList()));
    await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());
  }

  /// Retourne le timestamp de dernière synchronisation
  static Future<DateTime?> getLastSync() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_lastSyncKey);
    return s != null ? DateTime.parse(s) : null;
  }

  /// Invalide le cache (force un refresh au prochain accès)
  static Future<void> invalidate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastSyncKey);
  }
}
```

### 4.2 Fetch intelligent au lancement

```dart
class SOSQuestionsProvider extends ChangeNotifier {
  List<SOSQuestion> _questions = [];
  String _selectedLang = 'fr';
  bool _loading = true;
  RealtimeChannel? _channel;

  List<SOSQuestion> get questions => _questions;
  String get selectedLang => _selectedLang;
  bool get loading => _loading;

  void setLanguage(String lang) {
    _selectedLang = lang;
    notifyListeners();
  }

  /// Initialise : charge le cache, puis vérifie si une mise à jour est nécessaire
  Future<void> initialize() async {
    // 1. Charger le cache immédiatement pour un affichage instantané
    final cached = await SOSQuestionsCache.loadFromCache();
    if (cached != null && cached.isNotEmpty) {
      _questions = cached;
      _loading = false;
      notifyListeners();
    }

    // 2. Vérifier si le cache est à jour
    final lastSync = await SOSQuestionsCache.getLastSync();
    final needsRefresh = await _checkNeedsRefresh(lastSync);

    if (needsRefresh || cached == null) {
      await _fetchFromServer();
    }

    // 3. S'abonner au Realtime pour les mises à jour en direct
    _subscribeToRealtime();
  }

  /// Compare le MAX(updated_at) serveur avec le dernier sync local
  Future<bool> _checkNeedsRefresh(DateTime? lastSync) async {
    if (lastSync == null) return true;

    final response = await Supabase.instance.client
        .from('sos_questions')
        .select('updated_at')
        .order('updated_at', ascending: false)
        .limit(1)
        .single();

    final serverUpdatedAt = DateTime.parse(response['updated_at']);
    return serverUpdatedAt.isAfter(lastSync);
  }

  /// Fetch toutes les questions actives depuis le serveur
  Future<void> _fetchFromServer() async {
    _loading = true;
    notifyListeners();

    final response = await Supabase.instance.client
        .from('sos_questions')
        .select('*')
        .eq('is_active', true)
        .order('display_order');

    _questions = (response as List).map((e) => SOSQuestion.fromJson(e)).toList();
    await SOSQuestionsCache.saveToCache(_questions);

    _loading = false;
    notifyListeners();
  }

  /// Écoute les modifications en temps réel et invalide le cache
  void _subscribeToRealtime() {
    _channel = Supabase.instance.client
        .channel('sos-questions-mobile-${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'sos_questions',
          callback: (payload) async {
            // Invalider le cache et re-fetcher
            await SOSQuestionsCache.invalidate();
            await _fetchFromServer();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }
}
```

---

## 5. Logique conditionnelle (questions en cascade)

```dart
/// Filtre les questions visibles en fonction des réponses actuelles
List<SOSQuestion> getVisibleQuestions(
  List<SOSQuestion> allQuestions,
  String template,
  Map<String, String> answers,
) {
  return allQuestions
      .where((q) => q.template == template && q.isActive)
      .where((q) {
        // Question racine : toujours visible
        if (q.parentQuestionKey == null) return true;
        // Question conditionnelle : vérifier la réponse parente
        final parentAnswer = answers[q.parentQuestionKey];
        if (parentAnswer == null) return false;
        if (q.showIfAnswer == null) return true;
        return q.showIfAnswer!.contains(parentAnswer);
      })
      .toList()
    ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
}
```

---

## 6. Score de gravité

```dart
/// Calcule le score de gravité total à partir des réponses
int calculateGravityScore(
  List<SOSQuestion> questions,
  Map<String, String> answers,
) {
  int total = 0;
  for (final entry in answers.entries) {
    final question = questions.firstWhereOrNull((q) => q.questionKey == entry.key);
    if (question == null) continue;
    final option = question.options.firstWhereOrNull((o) => o.label == entry.value);
    total += option?.weight ?? 0;
  }
  return total;
}

/// Retourne le niveau de gravité
String getGravityLevel(int score) {
  if (score >= 7) return 'critical';   // Rouge
  if (score >= 4) return 'high';       // Orange
  return 'low';                        // Vert
}
```

---

## 7. Affichage des questions avec traduction

```dart
class SOSQuestionWidget extends StatelessWidget {
  final SOSQuestion question;
  final String selectedLang;
  final String? currentAnswer;
  final Function(String) onAnswer;

  @override
  Widget build(BuildContext context) {
    final text = question.getLocalizedText(selectedLang);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: TextStyle(fontWeight: FontWeight.w600)),
        if (question.isRequired)
          Text('*', style: TextStyle(color: Colors.red)),
        SizedBox(height: 8),
        if (question.questionType == 'single_choice' || question.questionType == 'boolean')
          Wrap(
            spacing: 8,
            children: question.options.asMap().entries.map((entry) {
              final i = entry.key;
              final opt = entry.value;
              final label = question.getLocalizedOption(i, selectedLang);
              final isSelected = currentAnswer == opt.label;
              
              return ChoiceChip(
                label: Text(label),
                selected: isSelected,
                onSelected: (_) => onAnswer(opt.label), // stocke toujours la valeur FR comme clé
              );
            }).toList(),
          ),
        if (question.questionType == 'text')
          TextField(onChanged: onAnswer),
      ],
    );
  }
}
```

### Règle critique : stockage des réponses

> **Les réponses sont TOUJOURS stockées avec le label FR** (`opt.label`) comme valeur, quel que soit la langue d'affichage. Cela garantit la cohérence des données en base et le bon fonctionnement de la logique conditionnelle (`show_if_answer` compare les valeurs FR).

---

## 8. Flux complet

```
App Launch
  └─ SOSQuestionsProvider.initialize()
       ├─ Charger cache local → affichage immédiat
       ├─ Comparer MAX(updated_at) serveur vs last_sync
       │    └─ Si plus récent → re-fetch + sauvegarder cache
       └─ S'abonner Realtime (postgres_changes sur sos_questions)
            └─ Sur changement → invalider cache + re-fetch

Appel SOS
  └─ Écran sélection langue (FR / EN / LN / SW)
       └─ Écran questionnaire
            ├─ Filtrer par template (catégorie d'urgence)
            ├─ Afficher questions racines traduites
            ├─ Sur réponse → révéler questions conditionnelles
            ├─ Calculer score gravité en temps réel
            └─ Envoyer réponses à sos_responses (labels FR)
```

---

## 9. Résumé des règles

| Règle | Détail |
|---|---|
| **Langue par défaut** | FR (stocké dans `question_text` et `options[].label`) |
| **Fallback** | Si `translations[lang].text` est vide → afficher `question_text` |
| **Options fallback** | Si `translations[lang].options[i]` est vide → afficher `options[i].label` |
| **Stockage réponses** | Toujours en FR (`opt.label`), jamais en langue traduite |
| **Cache** | SharedPreferences/Hive, invalidé par Realtime |
| **Refresh** | Comparer `MAX(updated_at)` serveur vs `last_sync` local |
| **Realtime** | Canal unique par instance, `postgres_changes` sur `sos_questions` |
| **Conditionnelle** | `show_if_answer` compare avec la valeur FR de la réponse parente |
| **Score gravité** | Somme des `weight` des options choisies |
