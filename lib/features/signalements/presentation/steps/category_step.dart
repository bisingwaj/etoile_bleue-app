import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';
import '../../providers/signalement_draft_provider.dart';
import '../../models/signalement_enums.dart';

class CategoryStep extends ConsumerWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;

  static const _categoryIcons = <SignalementCategory, IconData>{
    SignalementCategory.corruption: CupertinoIcons.money_dollar_circle_fill,
    SignalementCategory.detournementMedicaments: CupertinoIcons.bandage_fill,
    SignalementCategory.maltraitance: CupertinoIcons.hand_raised_fill,
    SignalementCategory.surfacturation: CupertinoIcons.creditcard_fill,
    SignalementCategory.personnelFantome: CupertinoIcons.person_crop_circle_badge_xmark,
    SignalementCategory.medicamentsPerimes: CupertinoIcons.timer,
    SignalementCategory.fauxDiplomes: CupertinoIcons.doc_text_fill,
    SignalementCategory.insalubrite: CupertinoIcons.drop_fill,
    SignalementCategory.violenceHarcelement: CupertinoIcons.shield_fill,
    SignalementCategory.discrimination: CupertinoIcons.equal_circle_fill,
    SignalementCategory.negligenceMedicale: CupertinoIcons.heart_slash_fill,
    SignalementCategory.traficOrganes: CupertinoIcons.exclamationmark_octagon_fill,
    SignalementCategory.racketUrgences: CupertinoIcons.exclamationmark_triangle_fill,
    SignalementCategory.detournementAide: CupertinoIcons.cube_box_fill,
    SignalementCategory.absenceInjustifiee: CupertinoIcons.calendar_badge_minus,
    SignalementCategory.conditionsTravail: CupertinoIcons.hammer_fill,
    SignalementCategory.protocolesSanitaires: CupertinoIcons.doc_text_fill,
    SignalementCategory.falsificationCertificats: CupertinoIcons.doc_on_clipboard_fill,
    SignalementCategory.ruptureStock: CupertinoIcons.archivebox_fill,
    SignalementCategory.exploitationStagiaires: CupertinoIcons.person_2_fill,
    SignalementCategory.abusSexuels: CupertinoIcons.eye_slash_fill,
    SignalementCategory.obstructionEnquetes: CupertinoIcons.nosign,
  };

  const CategoryStep({super.key, required this.onNext, required this.onBack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(signalementDraftProvider);
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    final canProceed = draft.category != null;

    return Container(
      color: Colors.transparent,
      child: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top + 20),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFEBF4FF), Color(0xFFF3F4F6)], // Soft elegant background
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(CupertinoIcons.chevron_back, size: 26, color: AppColors.navy),
                          onPressed: onBack,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Type d'incident",
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

                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            const Text(
                              "Quelle est la nature du problème ?",
                              style: TextStyle(fontFamily: 'Marianne', fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.navy),
                            ),
                            const SizedBox(height: 16),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: SignalementCategory.values.length,
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 16,
                                crossAxisSpacing: 16,
                                childAspectRatio: 1.05,
                              ),
                              itemBuilder: (ctx, i) {
                                final cat = SignalementCategory.values[i];
                                final isSelected = cat == draft.category;

                                return GestureDetector(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    ref.read(signalementDraftProvider.notifier).setCategory(cat);
                                    // Auto-advance
                                    Future.delayed(const Duration(milliseconds: 200), () {
                                      if (context.mounted) onNext();
                                    });
                                  },
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(20),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: isSelected ? AppColors.blue.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.4),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(
                                            color: isSelected ? AppColors.blue : Colors.white.withValues(alpha: 0.6),
                                            width: isSelected ? 2 : 1,
                                          ),
                                          boxShadow: [
                                            if (!isSelected) BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
                                          ],
                                        ),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              _categoryIcons[cat] ?? CupertinoIcons.tag_fill,
                                              size: 38,
                                              color: isSelected ? AppColors.blue : AppColors.navy.withValues(alpha: 0.8),
                                            ),
                                            const SizedBox(height: 12),
                                            Expanded(
                                              child: Center(
                                                child: Text(
                                                  cat.localizedLabel,
                                                  textAlign: TextAlign.center,
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontFamily: 'Marianne',
                                                    fontSize: 14,
                                                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                                                    color: isSelected ? AppColors.blue : AppColors.navy.withValues(alpha: 0.9),
                                                    height: 1.2,
                                                    letterSpacing: -0.3,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ).animate().fadeIn(duration: 400.ms, curve: Curves.easeOutCubic).slideY(begin: 0.05, end: 0, duration: 400.ms, curve: Curves.easeOutCubic),
                            const SizedBox(height: 48),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Bottom Action
                  Container(
                    padding: EdgeInsets.fromLTRB(24, 16, 24, bottomPad > 0 ? bottomPad + 16 : MediaQuery.of(context).padding.bottom + 16),
                    decoration: BoxDecoration(
                      color: Colors.transparent, // Let gradient show
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: canProceed ? () { HapticFeedback.mediumImpact(); onNext(); } : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.navy,
                          disabledBackgroundColor: const Color(0xFFE5E7EB),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: Text(
                          "Continuer",
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
}
