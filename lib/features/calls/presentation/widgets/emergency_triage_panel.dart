import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:etoile_bleue_mobile/core/providers/call_state_provider.dart';
import 'package:etoile_bleue_mobile/core/providers/sos_questions_provider.dart';
import 'package:etoile_bleue_mobile/core/services/emergency_call_service.dart';
import 'package:etoile_bleue_mobile/features/calls/data/sos_question_model.dart';

class EmergencyTriagePanel extends ConsumerStatefulWidget {
  const EmergencyTriagePanel({super.key});

  @override
  ConsumerState<EmergencyTriagePanel> createState() => _EmergencyTriagePanelState();
}

class _EmergencyTriagePanelState extends ConsumerState<EmergencyTriagePanel> {
  final Map<String, String> _answers = {};
  bool _submitted = false;
  int _currentVisibleIndex = 0;

  /// Fallback static questions used when the server has no data
  static final _fallbackQuestions = [
    SOSQuestion(
      id: 'fallback-1',
      questionKey: 'category',
      questionText: "Nature de l'urgence ?",
      questionType: 'single_choice',
      options: [
        SOSQuestionOption(label: 'Malaise', weight: 2),
        SOSQuestionOption(label: 'Accident', weight: 3),
        SOSQuestionOption(label: 'Agressions', weight: 3),
        SOSQuestionOption(label: 'Incendie', weight: 3),
        SOSQuestionOption(label: 'Autre', weight: 1),
      ],
      displayOrder: 0,
      isActive: true,
      isRequired: true,
      category: 'triage',
      template: 'default',
      translations: {},
      updatedAt: DateTime.now(),
    ),
    SOSQuestion(
      id: 'fallback-2',
      questionKey: 'isConscious',
      questionText: 'La victime est-elle consciente ?',
      questionType: 'boolean',
      options: [
        SOSQuestionOption(label: 'Oui, répond', weight: 0),
        SOSQuestionOption(label: 'Non', weight: 4),
      ],
      displayOrder: 1,
      isActive: true,
      isRequired: true,
      category: 'triage',
      template: 'default',
      translations: {},
      updatedAt: DateTime.now(),
    ),
    SOSQuestion(
      id: 'fallback-3',
      questionKey: 'isBreathing',
      questionText: 'La victime respire-t-elle ?',
      questionType: 'boolean',
      options: [
        SOSQuestionOption(label: 'Oui, respire', weight: 0),
        SOSQuestionOption(label: 'Non', weight: 5),
      ],
      displayOrder: 2,
      isActive: true,
      isRequired: true,
      category: 'triage',
      template: 'default',
      translations: {},
      updatedAt: DateTime.now(),
    ),
  ];

  void _selectAnswer(String questionKey, String questionText, String value, List<SOSQuestion> allQuestions) async {
    final callState = ref.read(callStateProvider);

    setState(() {
      _answers[questionKey] = value;
    });

    // Recalculate score after this answer
    final score = calculateGravityScore(allQuestions, _answers);
    final level = getGravityLevel(score);

    // Upsert one row per answer into sos_responses (dashboard contract)
    final incidentId = callState.incidentId;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (incidentId != null && userId != null) {
      ref.read(sosQuestionsProvider.notifier).upsertResponse(
        incidentId: incidentId,
        citizenId: userId,
        questionKey: questionKey,
        questionText: questionText,
        answer: value,
        gravityScore: score,
        gravityLevel: level,
        callId: callState.callHistoryId,
      );
    }

    // Also update triage_data on call_history for backward compatibility
    final channelName = callState.channelName;
    if (channelName != null && channelName.isNotEmpty) {
      ref.read(emergencyCallServiceProvider).updateTriageData(channelName, _answers);
    }

    // Check if we should advance or are done
    final visible = getVisibleQuestions(allQuestions, 'default', _answers);
    final nextIndex = _currentVisibleIndex + 1;
    if (nextIndex >= visible.length) {
      setState(() => _submitted = true);
    } else {
      setState(() => _currentVisibleIndex = nextIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) return _buildCompletionCard();

    final questionsAsync = ref.watch(sosQuestionsProvider);

    final allQuestions = questionsAsync.maybeWhen(
      data: (qs) => qs.isNotEmpty ? qs : _fallbackQuestions,
      orElse: () => _fallbackQuestions,
    );

    final visible = getVisibleQuestions(allQuestions, 'default', _answers);
    if (visible.isEmpty) return _buildCompletionCard();

    final safeIndex = _currentVisibleIndex.clamp(0, visible.length - 1);
    final current = visible[safeIndex];

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0.0, 0.2), end: Offset.zero).animate(animation),
            child: child,
          ),
        );
      },
      child: Container(
        key: ValueKey<String>('q-${current.questionKey}'),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Progress indicator
            Row(
              children: [
                Text(
                  '${safeIndex + 1}/${visible.length}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (safeIndex + 1) / visible.length,
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                      minHeight: 3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Question text
            Text(
              current.getLocalizedText('fr'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            // Options
            _buildOptionsForQuestion(current, allQuestions),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionsForQuestion(SOSQuestion question, List<SOSQuestion> allQuestions) {
    if (question.questionType == 'boolean' && question.options.length == 2) {
      return Row(
        children: [
          Expanded(
            child: _buildOptionChip(
              question.getLocalizedOption(0, 'fr'),
              () => _selectAnswer(question.questionKey, question.questionText, question.options[0].label, allQuestions),
              color: Colors.green,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildOptionChip(
              question.getLocalizedOption(1, 'fr'),
              () => _selectAnswer(question.questionKey, question.questionText, question.options[1].label, allQuestions),
              color: Colors.red,
            ),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(question.options.length, (i) {
        return _buildOptionChip(
          question.getLocalizedOption(i, 'fr'),
          () => _selectAnswer(question.questionKey, question.questionText, question.options[i].label, allQuestions),
        );
      }),
    );
  }

  Widget _buildCompletionCard() {
    final allQuestions = ref.read(sosQuestionsProvider).maybeWhen(
      data: (qs) => qs.isNotEmpty ? qs : _fallbackQuestions,
      orElse: () => _fallbackQuestions,
    );
    final score = calculateGravityScore(allQuestions, _answers);
    final level = getGravityLevel(score);

    Color badgeColor;
    String badgeLabel;
    switch (level) {
      case 'critical':
        badgeColor = Colors.red;
        badgeLabel = 'Urgence critique';
        break;
      case 'high':
        badgeColor = Colors.orange;
        badgeLabel = 'Urgence élevée';
        break;
      default:
        badgeColor = Colors.green;
        badgeLabel = 'Urgence modérée';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(CupertinoIcons.checkmark_seal_fill, color: Colors.green),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Informations transmises au centre d\'appel.',
                  style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
            ),
            child: Text(
              badgeLabel,
              style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionChip(String label, VoidCallback onTap, {Color color = Colors.blue}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
