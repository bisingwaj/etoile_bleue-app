import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';
import '../../providers/signalement_draft_provider.dart';
import '../../providers/signalement_providers.dart';

class LocationStep extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;

  const LocationStep({super.key, required this.onNext, required this.onBack});

  @override
  ConsumerState<LocationStep> createState() => _LocationStepState();
}

class _LocationStepState extends ConsumerState<LocationStep> {
  late TextEditingController _structureCtrl;
  Timer? _searchDebounce;
  List<Map<String, dynamic>> _structureResults = [];
  bool _structureDropdownOpen = false;

  final List<String> _kinshasaCommunes = [
    'Bandalungwa', 'Barumbu', 'Bumbu', 'Gombe', 'Kalamu', 'Kasa-Vubu', 
    'Kimbanseke', 'Kinshasa', 'Kintambo', 'Kisenso', 'Lemba', 'Limete', 
    'Lingwala', 'Makala', 'Maluku', 'Masina', 'Matete', 'Mont-Ngafula', 
    'Ndjili', 'Ngaba', 'Ngaliema', 'Ngiri-Ngiri', 'Nsele', 'Selembao'
  ];

  @override
  void initState() {
    super.initState();
    final draft = ref.read(signalementDraftProvider);
    _structureCtrl = TextEditingController(text: draft.structure?['name'] as String? ?? '');
  }

  @override
  void dispose() {
    _structureCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onStructureSearch(String query) {
    _searchDebounce?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _structureResults = [];
        _structureDropdownOpen = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final results = await ref.read(structureSearchProvider(query.trim()).future);
        if (mounted) {
          setState(() {
            _structureResults = results;
            _structureDropdownOpen = results.isNotEmpty;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _structureResults = [];
            _structureDropdownOpen = false;
          });
        }
      }
    });
  }

  void _selectStructure(Map<String, dynamic> s) {
    HapticFeedback.selectionClick();
    ref.read(signalementDraftProvider.notifier).setStructure(s);
    _structureCtrl.text = s['name'] as String? ?? '';
    setState(() {
      _structureDropdownOpen = false;
      _structureResults = [];
    });
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(signalementDraftProvider);
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    
    // Le lieu peut-être optionnel si GPS présent, mais ici on le force ou non selon votre choix.
    // On permet d'avancer quoi qu'il arrive, ou on force "commune". On force commune ici.
    final canProceed = draft.commune != null && draft.commune!.isNotEmpty;

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
                        const Expanded(
                          child: Text(
                            "Localisation",
                            style: TextStyle(
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
                              "Où l'incident s'est-il produit ?",
                              style: TextStyle(fontFamily: 'Marianne', fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.navy),
                            ),
                            const SizedBox(height: 16),

                            GestureDetector(
                              onTap: _showCommuneSelector,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: draft.commune != null ? AppColors.blue : const Color(0xFFD1D5DB), width: 1.5),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      draft.commune ?? "Sélectionner la commune",
                                      style: TextStyle(
                                        fontFamily: 'Marianne',
                                        fontSize: 16,
                                        fontWeight: draft.commune != null ? FontWeight.w700 : FontWeight.w600,
                                        color: draft.commune != null ? AppColors.navy : const Color(0xFF9CA3AF),
                                      ),
                                    ),
                                    Icon(CupertinoIcons.chevron_down, color: draft.commune != null ? AppColors.blue : const Color(0xFF9CA3AF), size: 20),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 24),
                            // Structure
                            const Text(
                              "Structure concernée (Optionnel)",
                              style: TextStyle(fontFamily: 'Marianne', fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.navy),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFD1D5DB), width: 1.5),
                              ),
                              child: TextField(
                                controller: _structureCtrl,
                                onChanged: _onStructureSearch,
                                style: const TextStyle(fontFamily: 'Marianne', fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.navy),
                                decoration: const InputDecoration(
                                  hintText: "Hôpital, Centre de santé...",
                                  hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 15),
                                  prefixIcon: Icon(CupertinoIcons.search, color: Color(0xFF9CA3AF)),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                ),
                              ),
                            ),

                            if (_structureDropdownOpen)
                              Container(
                                margin: const EdgeInsets.only(top: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFE5E7EB)),
                                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
                                ),
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  padding: EdgeInsets.zero,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _structureResults.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE5E7EB)),
                                  itemBuilder: (context, index) {
                                    final s = _structureResults[index];
                                    return ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                      title: Text(s['name'] as String? ?? '', style: const TextStyle(fontFamily: 'Marianne', fontWeight: FontWeight.w700, color: AppColors.navy)),
                                      subtitle: s['commune'] != null ? Text(s['commune'] as String, style: const TextStyle(fontFamily: 'Marianne', color: AppColors.textSecondary)) : null,
                                      onTap: () => _selectStructure(s),
                                    );
                                  },
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

  void _showCommuneSelector() {
    FocusScope.of(context).unfocus();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Commune de l'incident",
                style: TextStyle(fontFamily: 'Marianne', fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.navy),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  itemCount: _kinshasaCommunes.length,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (c, i) {
                    final isSelected = ref.read(signalementDraftProvider).commune == _kinshasaCommunes[i];
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        ref.read(signalementDraftProvider.notifier).setCommune(_kinshasaCommunes[i]);
                        Navigator.pop(ctx);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.blue.withValues(alpha: 0.1) : const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isSelected ? AppColors.blue : const Color(0xFFE5E7EB), width: 1.5),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _kinshasaCommunes[i],
                              style: TextStyle(fontFamily: 'Marianne', fontSize: 16, fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600, color: isSelected ? AppColors.blue : AppColors.navy),
                            ),
                            if (isSelected) const Icon(CupertinoIcons.checkmark_alt_circle_fill, color: AppColors.blue),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
}
