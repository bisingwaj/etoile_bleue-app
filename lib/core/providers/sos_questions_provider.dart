import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:etoile_bleue_mobile/features/calls/data/sos_question_model.dart';
import 'package:etoile_bleue_mobile/features/calls/data/sos_questions_cache.dart';

final sosQuestionsProvider = StateNotifierProvider<SOSQuestionsNotifier, AsyncValue<List<SOSQuestion>>>((ref) {
  final notifier = SOSQuestionsNotifier();
  ref.onDispose(notifier.dispose);
  return notifier;
});

class SOSQuestionsNotifier extends StateNotifier<AsyncValue<List<SOSQuestion>>> {
  SOSQuestionsNotifier() : super(const AsyncValue.loading());

  RealtimeChannel? _channel;
  final _supabase = Supabase.instance.client;

  Future<void> initialize() async {
    try {
      final cached = await SOSQuestionsCache.loadFromCache();
      if (cached != null && cached.isNotEmpty) {
        state = AsyncValue.data(cached);
      }

      await _fetchFromServer();
      _subscribeRealtime();
    } catch (e, st) {
      if (state.value == null || state.value!.isEmpty) {
        state = AsyncValue.error(e, st);
      }
      debugPrint('[SOSQuestions] initialize error: $e');
    }
  }

  Future<void> _fetchFromServer() async {
    try {
      final data = await _supabase
          .from('sos_questions')
          .select('id, question_text, question_type, options, display_order, is_active')
          .eq('is_active', true)
          .order('display_order', ascending: true);

      final questions = (data as List).map((e) => SOSQuestion.fromJson(e as Map<String, dynamic>)).toList();
      state = AsyncValue.data(questions);
      await SOSQuestionsCache.saveToCache(questions);
      debugPrint('[SOSQuestions] Fetched ${questions.length} questions from server');
    } catch (e, st) {
      debugPrint('[SOSQuestions] Fetch error: $e');
      if (state.value == null || state.value!.isEmpty) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  void _subscribeRealtime() {
    _channel?.unsubscribe();
    _channel = _supabase
        .channel('sos-questions-${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'sos_questions',
          callback: (payload) {
            debugPrint('[SOSQuestions] Realtime event: ${payload.eventType}');
            _fetchFromServer();
          },
        )
        .subscribe();
  }

  /// Upserts a single SOS response row per question (dashboard contract).
  /// Called immediately each time the citizen answers a question.
  Future<void> upsertResponse({
    required String incidentId,
    required String citizenId,
    required String questionKey,
    required String questionText,
    required String answer,
    required int gravityScore,
    required String gravityLevel,
    String? callId,
  }) async {
    try {
      await _supabase.from('sos_responses').upsert(
        {
          'incident_id': incidentId,
          'citizen_id': citizenId,
          'call_id': callId,
          'question_key': questionKey,
          'question_text': questionText,
          'answer': answer,
          'answered_at': DateTime.now().toUtc().toIso8601String(),
          'gravity_score': gravityScore,
          'gravity_level': gravityLevel,
          'answers': {questionKey: answer},
        },
        onConflict: 'incident_id,question_key',
      );
      debugPrint('[SOSQuestions] Upserted response: $questionKey=$answer (score=$gravityScore)');
    } catch (e) {
      debugPrint('[SOSQuestions] Upsert error: $e');
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }
}
