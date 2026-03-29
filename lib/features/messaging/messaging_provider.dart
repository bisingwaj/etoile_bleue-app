/// messaging_provider.dart — Messagerie Supabase Realtime pour Flutter
/// Permet aux citoyens/secouristes d'envoyer et recevoir des messages texte/audio

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatMessage {
  final String id;
  final String senderId;
  final String recipientId;
  final String content;
  final String type; // 'text' | 'audio'
  final int? audioDuration;
  final DateTime createdAt;
  final bool isMine;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.content,
    required this.type,
    this.audioDuration,
    required this.createdAt,
    required this.isMine,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json, String currentUserId) {
    return ChatMessage(
      id: json['id'],
      senderId: json['sender_id'],
      recipientId: json['recipient_id'],
      content: json['content'],
      type: json['type'] ?? 'text',
      audioDuration: json['audio_duration'],
      createdAt: DateTime.parse(json['created_at']),
      isMine: json['sender_id'] == currentUserId,
    );
  }
}

class MessagingState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final String? error;

  MessagingState({this.messages = const [], this.isLoading = false, this.error});

  MessagingState copyWith({List<ChatMessage>? messages, bool? isLoading, String? error}) {
    return MessagingState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class MessagingNotifier extends StateNotifier<MessagingState> {
  final SupabaseClient _supabase;
  RealtimeChannel? _channel;
  String? _currentRecipientId;

  MessagingNotifier(this._supabase) : super(MessagingState());

  String get _userId => _supabase.auth.currentUser?.id ?? '';

  /// Charge les messages pour un destinataire et s'abonne au Realtime
  Future<void> openConversation(String recipientId) async {
    _currentRecipientId = recipientId;
    state = state.copyWith(isLoading: true);

    // Charger l'historique
    final response = await _supabase
        .from('messages')
        .select()
        .or('and(sender_id.eq.$_userId,recipient_id.eq.$recipientId),and(sender_id.eq.$recipientId,recipient_id.eq.$_userId)')
        .order('created_at', ascending: true)
        .limit(100);

    final messages = (response as List)
        .map((m) => ChatMessage.fromJson(m, _userId))
        .toList();

    state = state.copyWith(messages: messages, isLoading: false);

    // S'abonner au Realtime
    _channel?.unsubscribe();
    _channel = _supabase
        .channel('messages-$recipientId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final m = payload.newRecord;
            final isRelevant =
                (m['sender_id'] == _userId && m['recipient_id'] == recipientId) ||
                (m['sender_id'] == recipientId && m['recipient_id'] == _userId);

            if (isRelevant) {
              final msg = ChatMessage.fromJson(m, _userId);
              if (!state.messages.any((existing) => existing.id == msg.id)) {
                state = state.copyWith(messages: [...state.messages, msg]);
              }
            }
          },
        )
        .subscribe();
  }

  /// Envoie un message texte
  Future<void> sendText(String content) async {
    if (_currentRecipientId == null) return;

    await _supabase.from('messages').insert({
      'sender_id': _userId,
      'recipient_id': _currentRecipientId,
      'recipient_type': 'operator',
      'content': content,
      'type': 'text',
    });
  }

  /// Envoie un message audio
  Future<void> sendAudio({required String audioUrl, required int durationSeconds}) async {
    if (_currentRecipientId == null) return;

    await _supabase.from('messages').insert({
      'sender_id': _userId,
      'recipient_id': _currentRecipientId,
      'recipient_type': 'operator',
      'content': 'Message vocal',
      'type': 'audio',
      'audio_url': audioUrl,
      'audio_duration': durationSeconds,
    });
  }

  void closeConversation() {
    _channel?.unsubscribe();
    _channel = null;
    _currentRecipientId = null;
    state = MessagingState();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }
}

final messagingProvider = StateNotifierProvider<MessagingNotifier, MessagingState>((ref) {
  return MessagingNotifier(Supabase.instance.client);
});
