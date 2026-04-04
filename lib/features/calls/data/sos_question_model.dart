import 'dart:convert';

class SOSQuestionOption {
  final String label;
  final int weight;

  SOSQuestionOption({required this.label, required this.weight});

  factory SOSQuestionOption.fromJson(Map<String, dynamic> json) => SOSQuestionOption(
    label: json['label'] as String? ?? '',
    weight: json['weight'] as int? ?? 0,
  );

  Map<String, dynamic> toJson() => {'label': label, 'weight': weight};
}

class SOSQuestionTranslation {
  final String text;
  final List<String> options;

  SOSQuestionTranslation({required this.text, required this.options});

  factory SOSQuestionTranslation.fromJson(Map<String, dynamic> json) => SOSQuestionTranslation(
    text: json['text'] as String? ?? '',
    options: List<String>.from(json['options'] ?? []),
  );

  Map<String, dynamic> toJson() => {'text': text, 'options': options};
}

class SOSQuestion {
  final String id;
  final String questionKey;
  final String questionText;
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

  SOSQuestion({
    required this.id,
    required this.questionKey,
    required this.questionText,
    required this.questionType,
    required this.options,
    required this.displayOrder,
    required this.isActive,
    required this.isRequired,
    required this.category,
    required this.template,
    this.parentQuestionKey,
    this.showIfAnswer,
    required this.translations,
    required this.updatedAt,
  });

  factory SOSQuestion.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    List<SOSQuestionOption> parsedOptions = [];
    if (rawOptions is List) {
      parsedOptions = rawOptions.map((e) {
        if (e is Map<String, dynamic>) return SOSQuestionOption.fromJson(e);
        if (e is String) {
          try {
            return SOSQuestionOption.fromJson(jsonDecode(e));
          } catch (_) {}
        }
        return SOSQuestionOption(label: e.toString(), weight: 0);
      }).toList();
    } else if (rawOptions is String) {
      try {
        final decoded = jsonDecode(rawOptions) as List;
        parsedOptions = decoded.map((e) => SOSQuestionOption.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {}
    }

    final rawTranslations = json['translations'];
    Map<String, SOSQuestionTranslation> parsedTranslations = {};
    if (rawTranslations is Map) {
      for (final entry in rawTranslations.entries) {
        if (entry.value is Map<String, dynamic>) {
          parsedTranslations[entry.key as String] = SOSQuestionTranslation.fromJson(entry.value);
        }
      }
    } else if (rawTranslations is String) {
      try {
        final decoded = jsonDecode(rawTranslations) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          if (entry.value is Map<String, dynamic>) {
            parsedTranslations[entry.key] = SOSQuestionTranslation.fromJson(entry.value);
          }
        }
      } catch (_) {}
    }

    final rawShowIf = json['show_if_answer'];
    List<String>? parsedShowIf;
    if (rawShowIf is List) {
      parsedShowIf = rawShowIf.cast<String>();
    } else if (rawShowIf is String) {
      try {
        parsedShowIf = (jsonDecode(rawShowIf) as List).cast<String>();
      } catch (_) {}
    }

    return SOSQuestion(
      id: json['id'] as String? ?? '',
      questionKey: json['question_key'] as String? ?? '',
      questionText: json['question_text'] as String? ?? '',
      questionType: json['question_type'] as String? ?? 'single_choice',
      options: parsedOptions,
      displayOrder: json['display_order'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      isRequired: json['is_required'] as bool? ?? false,
      category: json['category'] as String? ?? 'triage',
      template: json['template'] as String? ?? 'default',
      parentQuestionKey: json['parent_question_key'] as String?,
      showIfAnswer: parsedShowIf,
      translations: parsedTranslations,
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'question_key': questionKey,
    'question_text': questionText,
    'question_type': questionType,
    'options': options.map((o) => o.toJson()).toList(),
    'display_order': displayOrder,
    'is_active': isActive,
    'is_required': isRequired,
    'category': category,
    'template': template,
    'parent_question_key': parentQuestionKey,
    'show_if_answer': showIfAnswer,
    'translations': translations.map((k, v) => MapEntry(k, v.toJson())),
    'updated_at': updatedAt.toIso8601String(),
  };

  /// Returns the localized question text, falling back to FR default
  String getLocalizedText(String lang) {
    if (lang == 'fr') return questionText;
    return translations[lang]?.text ?? questionText;
  }

  /// Returns the localized option label at [index], falling back to FR default
  String getLocalizedOption(int index, String lang) {
    if (index >= options.length) return '';
    if (lang == 'fr') return options[index].label;
    final translated = translations[lang]?.options;
    if (translated != null && index < translated.length && translated[index].isNotEmpty) {
      return translated[index];
    }
    return options[index].label;
  }
}

/// Filters visible questions based on template, active status, and conditional logic
List<SOSQuestion> getVisibleQuestions(
  List<SOSQuestion> allQuestions,
  String template,
  Map<String, String> answers,
) {
  return allQuestions
      .where((q) => q.template == template && q.isActive)
      .where((q) {
        if (q.parentQuestionKey == null) return true;
        final parentAnswer = answers[q.parentQuestionKey];
        if (parentAnswer == null) return false;
        if (q.showIfAnswer == null) return true;
        return q.showIfAnswer!.contains(parentAnswer);
      })
      .toList()
    ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
}

/// Calculates the gravity score from answers
int calculateGravityScore(List<SOSQuestion> questions, Map<String, String> answers) {
  int total = 0;
  for (final entry in answers.entries) {
    final question = questions.where((q) => q.questionKey == entry.key).firstOrNull;
    if (question == null) continue;
    final option = question.options.where((o) => o.label == entry.value).firstOrNull;
    total += option?.weight ?? 0;
  }
  return total;
}

/// Returns the gravity level label from a score
String getGravityLevel(int score) {
  if (score >= 7) return 'critical';
  if (score >= 4) return 'high';
  return 'low';
}
