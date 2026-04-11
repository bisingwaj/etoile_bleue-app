import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/signalement_enums.dart';
import '../models/signalement_models.dart';

class SignalementDraft {
  final List<PendingMediaFile> media;
  final SignalementCategory? category;
  final SignalementPriority priority;
  final String title;
  final String description;
  final bool isAnonymous;
  final String? commune;
  final Map<String, dynamic>? structure;
  final String? audioNotePath;
  final int? audioNoteDuration;

  const SignalementDraft({
    this.media = const [],
    this.category,
    this.priority = SignalementPriority.moyenne,
    this.title = '',
    this.description = '',
    this.isAnonymous = false,
    this.commune,
    this.structure,
    this.audioNotePath,
    this.audioNoteDuration,
  });

  SignalementDraft copyWith({
    List<PendingMediaFile>? media,
    SignalementCategory? category,
    bool clearCategory = false,
    SignalementPriority? priority,
    String? title,
    String? description,
    bool? isAnonymous,
    String? commune,
    bool clearCommune = false,
    Map<String, dynamic>? structure,
    bool clearStructure = false,
    String? audioNotePath,
    bool clearAudioNote = false,
    int? audioNoteDuration,
  }) {
    return SignalementDraft(
      media: media ?? this.media,
      category: clearCategory ? null : (category ?? this.category),
      priority: priority ?? this.priority,
      title: title ?? this.title,
      description: description ?? this.description,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      commune: clearCommune ? null : (commune ?? this.commune),
      structure: clearStructure ? null : (structure ?? this.structure),
      audioNotePath: clearAudioNote ? null : (audioNotePath ?? this.audioNotePath),
      audioNoteDuration: clearAudioNote ? null : (audioNoteDuration ?? this.audioNoteDuration),
    );
  }

  bool get hasMedia => media.isNotEmpty;
  bool get hasCategory => category != null;
  bool get hasRequiredFields => title.trim().isNotEmpty && description.trim().isNotEmpty;
  int get photoCount => media.where((f) => f.type == 'image').length;
  int get videoCount => media.where((f) => f.type == 'video').length;
  int get audioCount => media.where((f) => f.type == 'audio').length;
}

class SignalementDraftNotifier extends StateNotifier<SignalementDraft> {
  SignalementDraftNotifier() : super(const SignalementDraft());

  void addMedia(PendingMediaFile file) {
    state = state.copyWith(media: [...state.media, file]);
  }

  void removeMedia(int index) {
    final updated = [...state.media]..removeAt(index);
    state = state.copyWith(media: updated);
  }

  void setCategory(SignalementCategory cat) {
    state = state.copyWith(category: cat);
  }

  void setPriority(SignalementPriority p) {
    state = state.copyWith(priority: p);
  }

  void setTitle(String t) => state = state.copyWith(title: t);
  void setDescription(String d) => state = state.copyWith(description: d);
  void setAnonymous(bool v) => state = state.copyWith(isAnonymous: v);
  void setCommune(String? c) => state = state.copyWith(commune: c, clearCommune: c == null);
  void setStructure(Map<String, dynamic>? s) => state = state.copyWith(structure: s, clearStructure: s == null);

  void setAudioNote(String path, int duration) {
    state = state.copyWith(audioNotePath: path, audioNoteDuration: duration);
  }

  void clearAudioNote() {
    state = state.copyWith(clearAudioNote: true);
  }

  void reset() => state = const SignalementDraft();
}

final signalementDraftProvider =
    StateNotifierProvider.autoDispose<SignalementDraftNotifier, SignalementDraft>((ref) {
  return SignalementDraftNotifier();
});
