import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TranscriptionEntry {
  final String speaker;
  final String content;
  final bool isFinal;
  final int timestampMs;

  const TranscriptionEntry({
    required this.speaker,
    required this.content,
    this.isFinal = false,
    this.timestampMs = 0,
  });
}

/// Subscribes to Realtime INSERTs on `call_transcriptions` for a given
/// channel name and emits the growing list of transcriptions.
final transcriptionProvider =
    StreamProvider.family<List<TranscriptionEntry>, String>((ref, channelName) {
  final supabase = Supabase.instance.client;
  final entries = <TranscriptionEntry>[];
  final controller = StreamController<List<TranscriptionEntry>>();

  final realtimeChannel = supabase
      .channel('transcriptions-$channelName-${DateTime.now().millisecondsSinceEpoch}')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'call_transcriptions',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'call_id',
          value: channelName,
        ),
        callback: (payload) {
          final record = payload.newRecord;
          entries.add(TranscriptionEntry(
            speaker: record['speaker'] as String? ?? 'unknown',
            content: record['content'] as String? ?? '',
            isFinal: record['is_final'] as bool? ?? false,
            timestampMs: record['timestamp_ms'] as int? ?? 0,
          ));
          controller.add(List.unmodifiable(entries));
        },
      )
      .subscribe();

  ref.onDispose(() {
    realtimeChannel.unsubscribe();
    controller.close();
  });

  return controller.stream;
});
