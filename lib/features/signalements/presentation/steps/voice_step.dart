import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:record/record.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';
import '../../providers/signalement_draft_provider.dart';
import '../../data/signalement_media_processor.dart';
import '../../models/signalement_models.dart';

class VoiceStep extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;

  const VoiceStep({super.key, required this.onNext, required this.onBack});

  @override
  ConsumerState<VoiceStep> createState() => _VoiceStepState();
}

class _VoiceStepState extends ConsumerState<VoiceStep> {
  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  final _titleFocus = FocusNode();
  final _descFocus = FocusNode();

  final _recorder = AudioRecorder();
  bool _isRecordingAudio = false;
  int _audioSeconds = 0;
  Timer? _audioTimer;
  String? _recordedPath;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(signalementDraftProvider);
    _titleCtrl = TextEditingController(text: draft.title);
    _descCtrl = TextEditingController(text: draft.description);
    _recordedPath = draft.audioNotePath;
    _audioSeconds = draft.audioNoteDuration ?? 0;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _titleFocus.dispose();
    _descFocus.dispose();
    _audioTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    FocusScope.of(context).unfocus();
    if (_isRecordingAudio) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) return;
      final dir = Directory.systemTemp;
      final path = '${dir.path}/signalement_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000), path: path);
      setState(() {
        _isRecordingAudio = true;
        _audioSeconds = 0;
      });
      _audioTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_audioSeconds >= MediaLimits.maxAudioDuration) {
          _stopRecording();
          return;
        }
        setState(() => _audioSeconds++);
      });
      HapticFeedback.heavyImpact();
    } catch (e) {
      debugPrint('[Signalement] Audio record start error: $e');
    }
  }

  Future<void> _stopRecording() async {
    _audioTimer?.cancel();
    try {
      final path = await _recorder.stop();
      if (path != null) {
        final draft = ref.read(signalementDraftProvider);
        final oldAudioIdx = draft.media.lastIndexWhere((m) => m.type == 'audio');
        if (oldAudioIdx >= 0) {
          ref.read(signalementDraftProvider.notifier).removeMedia(oldAudioIdx);
        }

        setState(() => _recordedPath = path);
        ref.read(signalementDraftProvider.notifier).setAudioNote(path, _audioSeconds);
        ref.read(signalementDraftProvider.notifier).addMedia(PendingMediaFile(
          file: File(path),
          type: 'audio',
          originalFilename: 'voice_note.m4a',
          durationSeconds: _audioSeconds,
        ));
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      debugPrint('[Signalement] Audio record stop error: $e');
    }
    if (mounted) setState(() => _isRecordingAudio = false);
  }

  void _deleteAudioNote() {
    HapticFeedback.mediumImpact();
    ref.read(signalementDraftProvider.notifier).clearAudioNote();
    final draft = ref.read(signalementDraftProvider);
    final audioIndex = draft.media.lastIndexWhere((m) => m.type == 'audio');
    if (audioIndex >= 0) ref.read(signalementDraftProvider.notifier).removeMedia(audioIndex);
    setState(() => _recordedPath = null);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    final bool hasTextDesc = _descCtrl.text.trim().isNotEmpty;
    final bool hasAudioDesc = _recordedPath != null;
    final canProceed = (hasTextDesc || hasAudioDesc) && !_isRecordingAudio;

    return Container(
      color: Colors.transparent,
      child: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top + 20),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(CupertinoIcons.chevron_back, size: 26, color: AppColors.navy),
                          onPressed: widget.onBack,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'signalement.voice_page_title'.tr(),
                            style: const TextStyle(
                              fontFamily: 'Marianne',
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: AppColors.navy,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        // Bouton passer
                        if (!canProceed)
                           TextButton(
                             onPressed: () {
                               // Autoriser à passer quand même ? Pour l'instant non. La voix ou le texte sont requis.
                             },
                             child: Text('signalement.voice_required'.tr(), style: const TextStyle(color: AppColors.textSecondary, fontFamily: 'Marianne', fontWeight: FontWeight.normal)),
                           )
                      ],
                    ),
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            Text(
                              'signalement.voice_msg_recommended'.tr(),
                              style: const TextStyle(fontFamily: 'Marianne', fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.navy),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'signalement.voice_msg_explain'.tr(),
                              style: const TextStyle(fontFamily: 'Marianne', fontSize: 14, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 16),

                            if (_recordedPath != null && !_isRecordingAudio)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppColors.success.withValues(alpha: 0.3), width: 2),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                                      child: const Icon(CupertinoIcons.mic_fill, color: Colors.white, size: 24),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('signalement.voice_recorded'.tr(), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy, fontSize: 16)),
                                          Text(_formatDuration(_audioSeconds), style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700)),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(CupertinoIcons.trash_fill, color: AppColors.error),
                                      onPressed: _deleteAudioNote,
                                    )
                                  ],
                                ),
                              ).animate().scale(curve: Curves.easeOutBack, duration: 300.ms)
                            else
                              GestureDetector(
                                onTap: _toggleRecording,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 24),
                                  decoration: BoxDecoration(
                                    color: _isRecordingAudio ? AppColors.error.withValues(alpha: 0.1) : AppColors.blue.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: _isRecordingAudio ? AppColors.error : AppColors.blue, width: 2),
                                    boxShadow: _isRecordingAudio 
                                      ? [BoxShadow(color: AppColors.error.withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 2)]
                                      : [],
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        _isRecordingAudio ? CupertinoIcons.stop_circle_fill : CupertinoIcons.mic_circle_fill,
                                        size: 64,
                                        color: _isRecordingAudio ? AppColors.error : AppColors.blue,
                                      ).animate(target: _isRecordingAudio ? 1 : 0).scale(begin: const Offset(1, 1), end: const Offset(1.1, 1.1), duration: 500.ms).then().shake(),
                                      const SizedBox(height: 12),
                                      Text(
                                        _isRecordingAudio 
                                          ? 'signalement.voice_recording_progress'.tr(namedArgs: {'duration': _formatDuration(_audioSeconds)}) 
                                          : 'signalement.voice_tap_to_speak'.tr(),
                                        style: TextStyle(
                                          fontFamily: 'Marianne',
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: _isRecordingAudio ? AppColors.error : AppColors.blue,
                                        ),
                                      )
                                    ],
                                  ),
                                ),
                              ),

                            const SizedBox(height: 32),
                            Container(height: 1, color: AppColors.border.withValues(alpha: 0.3)),
                            const SizedBox(height: 24),

                            Text(
                              'signalement.voice_or_write'.tr(),
                              style: const TextStyle(fontFamily: 'Marianne', fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.navy),
                            ),
                            const SizedBox(height: 12),

                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFD1D5DB), width: 1.5),
                              ),
                              child: TextField(
                                controller: _titleCtrl,
                                focusNode: _titleFocus,
                                onChanged: (v) {
                                  ref.read(signalementDraftProvider.notifier).setTitle(v);
                                  setState(() {});
                                },
                                style: const TextStyle(fontFamily: 'Marianne', fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.navy),
                                decoration: InputDecoration(
                                  hintText: 'signalement.voice_title_hint'.tr(),
                                  hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 15),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                ),
                                textInputAction: TextInputAction.next,
                                onSubmitted: (_) => _descFocus.requestFocus(),
                              ),
                            ),
                            const SizedBox(height: 12),

                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFD1D5DB), width: 1.5),
                              ),
                              child: TextField(
                                controller: _descCtrl,
                                focusNode: _descFocus,
                                onChanged: (v) {
                                  ref.read(signalementDraftProvider.notifier).setDescription(v);
                                  setState(() {});
                                },
                                style: const TextStyle(fontFamily: 'Marianne', fontSize: 15, color: AppColors.navy, height: 1.5),
                                decoration: InputDecoration(
                                  hintText: 'signalement.voice_details_hint'.tr(),
                                  hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 15),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                ),
                                minLines: 3,
                                maxLines: 6,
                              ),
                            ),

                            const SizedBox(height: 48),
                          ],
                        ),
                      ),
                    ),
                  ),

                  Container(
                    padding: EdgeInsets.fromLTRB(24, 16, 24, bottomPad > 0 ? bottomPad + 16 : MediaQuery.of(context).padding.bottom + 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -4))],
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: canProceed ? () { HapticFeedback.mediumImpact(); widget.onNext(); } : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.navy,
                          disabledBackgroundColor: const Color(0xFFE5E7EB),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: Text(
                          'auth.continue_btn'.tr(),
                          style: TextStyle(
                            fontFamily: 'Marianne',
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: canProceed ? Colors.white : const Color(0xFF9CA3AF),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }
}
