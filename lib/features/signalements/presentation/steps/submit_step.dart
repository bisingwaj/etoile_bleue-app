import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';
import '../../providers/signalement_draft_provider.dart';
import '../../providers/signalement_providers.dart';

class SubmitStep extends ConsumerStatefulWidget {
  final VoidCallback onBack;

  const SubmitStep({super.key, required this.onBack});

  @override
  ConsumerState<SubmitStep> createState() => _SubmitStepState();
}

class _SubmitStepState extends ConsumerState<SubmitStep> {
  bool _isLocalSubmitting = false;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(signalementDraftProvider);
    // Force l'anonymat par défaut 
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!draft.isAnonymous) {
        ref.read(signalementDraftProvider.notifier).setAnonymous(true);
      }
    });
  }

  Future<void> _submit() async {
    if (_isLocalSubmitting) return;
    HapticFeedback.heavyImpact();
    final draft = ref.read(signalementDraftProvider);

    if (draft.category == null) {
      _showError('signalement.error_no_category'.tr());
      return;
    }
    if (draft.title.trim().isEmpty && draft.audioNotePath == null) {
      _showError("Veuillez fournir un titre ou un message vocal.");
      return;
    }

    setState(() => _isLocalSubmitting = true);

    try {
      final result = await ref.read(signalementSubmitProvider.notifier).submit(
        title: draft.title.trim().isNotEmpty ? draft.title.trim() : "Signalement Vocal",
        category: draft.category!.code,
        description: draft.description.trim(),
        commune: draft.commune,
        isAnonymous: draft.isAnonymous,
        priority: draft.priority.code,
        structureName: draft.structure?['name'] as String?,
        structureId: draft.structure?['id'] as String?,
        mediaFiles: draft.media,
      );

      if (result != null && mounted) {
        ref.read(signalementDraftProvider.notifier).reset();
        context.go('/signalement-success', extra: {
          'reference': result.reference,
          'mediaCount': result.mediaCount,
          'mediaUploaded': result.mediaUploaded,
          'pendingSync': result.pendingSync,
        });
      } else {
        if (mounted) setState(() => _isLocalSubmitting = false);
      }
    } catch (e) {
      debugPrint('[SubmitStep] Submit error: $e');
      if (mounted) {
        setState(() => _isLocalSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('signalement.error_unknown'.tr()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(signalementDraftProvider);
    final submitState = ref.watch(signalementSubmitProvider);
    final isSubmitting = submitState.status == SubmitState.submitting || _isLocalSubmitting;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

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
                          onPressed: isSubmitting ? null : widget.onBack,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'signalement.step_last'.tr(),
                            style: const TextStyle(
                              fontFamily: 'Marianne',
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: AppColors.navy,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Sécurité Banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    color: AppColors.success.withValues(alpha: 0.1),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(CupertinoIcons.lock_shield_fill, color: AppColors.success, size: 16),
                        const SizedBox(width: 8),
                        Text('signalement.secured_connection'.tr(), style: const TextStyle(fontFamily: 'Marianne', fontWeight: FontWeight.w700, color: AppColors.success, fontSize: 13)),
                      ],
                    ),
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 24),
                          
                          _MassiveAnonymityCard(
                            isAnonymous: draft.isAnonymous,
                            onChanged: isSubmitting ? null : (val) {
                               HapticFeedback.selectionClick();
                               ref.read(signalementDraftProvider.notifier).setAnonymous(val);
                            },
                          ),

                          const SizedBox(height: 32),
                          _SummaryCompact(draft: draft),
                          const SizedBox(height: 48),
                        ],
                      ),
                    ),
                  ),

                  // Submit Box
                  Container(
                    padding: EdgeInsets.fromLTRB(24, 16, 24, bottomPad > 0 ? bottomPad + 16 : MediaQuery.of(context).padding.bottom + 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -4))],
                    ),
                    child: Column(
                      children: [
                        if (submitState.status == SubmitState.error)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              submitState.errorMessage ?? 'signalement.error_submit_generic'.tr(),
                              style: const TextStyle(fontFamily: 'Marianne', fontSize: 14, color: AppColors.error, fontWeight: FontWeight.w700),
                            ),
                          ).animate().shake(),

                        _HugeSubmitButton(
                          isSubmitting: isSubmitting,
                          progress: submitState.progress,
                          onTap: _submit,
                        ),
                      ],
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
}

class _MassiveAnonymityCard extends StatelessWidget {
  final bool isAnonymous;
  final ValueChanged<bool>? onChanged;

  const _MassiveAnonymityCard({required this.isAnonymous, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged?.call(!isAnonymous),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isAnonymous ? AppColors.success.withValues(alpha: 0.1) : const Color(0xFFF0F2F5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isAnonymous ? AppColors.success : const Color(0xFFD1D5DB), width: 2),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isAnonymous ? AppColors.success : const Color(0xFF9CA3AF),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isAnonymous ? CupertinoIcons.shield_fill : CupertinoIcons.eye_slash_fill,
                color: Colors.white,
                size: 28,
              ),
            ).animate(target: isAnonymous ? 1 : 0).scale(begin: const Offset(1, 1), end: const Offset(1.1, 1.1)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'signalement.anonymous_label'.tr(),
                    style: TextStyle(fontFamily: 'Marianne', fontSize: 18, fontWeight: FontWeight.w800, color: isAnonymous ? AppColors.success : AppColors.navy),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isAnonymous ? 'signalement.submit_anon_hidden'.tr() : 'signalement.submit_anon_visible'.tr(),
                    style: TextStyle(fontFamily: 'Marianne', fontSize: 13, fontWeight: FontWeight.w600, color: isAnonymous ? AppColors.success : AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            CupertinoSwitch(
              value: isAnonymous,
              onChanged: onChanged,
              activeColor: AppColors.success,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCompact extends StatelessWidget {
  final SignalementDraft draft;
  const _SummaryCompact({required this.draft});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('signalement.summary_title'.tr(), style: const TextStyle(fontFamily: 'Marianne', fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          _row(CupertinoIcons.tag_fill, draft.category?.localizedLabel ?? 'signalement.summary_no_category'.tr()),
          if (draft.audioNotePath != null) _row(CupertinoIcons.mic_fill, 'signalement.summary_audio'.tr()),
          // check if there's no media besides the audio Note by verifying we don't have images/videos, etc.
          if (draft.media.where((m) => m.type != 'audio').isNotEmpty)
            _row(CupertinoIcons.photo_fill, 'signalement.summary_files'.tr(namedArgs: {'count': '${draft.media.where((m) => m.type != 'audio').length}'})),
          if (draft.commune?.isNotEmpty == true) _row(CupertinoIcons.location_solid, "${draft.commune}"),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.navy),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontFamily: 'Marianne', fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.navy))),
        ],
      ),
    );
  }
}

class _HugeSubmitButton extends StatelessWidget {
  final bool isSubmitting;
  final double progress;
  final VoidCallback onTap;

  const _HugeSubmitButton({required this.isSubmitting, required this.progress, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isSubmitting ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        height: 60,
        decoration: BoxDecoration(
          color: isSubmitting ? AppColors.navy.withValues(alpha: 0.8) : AppColors.blue,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSubmitting ? [] : [BoxShadow(color: AppColors.blue.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 4))],
        ),
        child: isSubmitting
             ? Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.transparent,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white30),
                        minHeight: 60,
                      ),
                    ),
                    Center(
                      child: Text(
                        'signalement.submit_sending'.tr(namedArgs: {'percent': '${(progress * 100).toInt()}'}),
                        style: const TextStyle(fontFamily: 'Marianne', fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white),
                      ),
                    )
                  ],
                )
             : Row(
                 mainAxisAlignment: MainAxisAlignment.center,
                 children: [
                   const Icon(CupertinoIcons.paperplane_fill, color: Colors.white, size: 22),
                   const SizedBox(width: 12),
                   Text('signalement.submit'.tr(), style: const TextStyle(fontFamily: 'Marianne', fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white)),
                 ],
               ),
      ),
    );
  }
}
