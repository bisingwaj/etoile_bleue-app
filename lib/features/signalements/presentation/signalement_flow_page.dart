import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'steps/camera_step.dart';
import 'steps/category_step.dart';
import 'steps/voice_step.dart';
import 'steps/location_step.dart';
import 'steps/submit_step.dart';
import '../providers/signalement_draft_provider.dart';

class SignalementFlowPage extends ConsumerStatefulWidget {
  const SignalementFlowPage({super.key});

  @override
  ConsumerState<SignalementFlowPage> createState() => _SignalementFlowPageState();
}

class _SignalementFlowPageState extends ConsumerState<SignalementFlowPage> {
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([]);
    super.dispose();
  }

  void _goTo(int page) {
    if (page < 0 || page > 4) return;
    HapticFeedback.selectionClick();
    setState(() => _currentPage = page);
  }

  void _next() => _goTo(_currentPage + 1);
  void _back() {
    if (_currentPage == 0) {
      Navigator.of(context).maybePop();
    } else {
      _goTo(_currentPage - 1);
    }
  }

  Future<bool> _onWillPop() async {
    if (_currentPage > 0) {
      _back();
      return false;
    }
    final draft = ref.read(signalementDraftProvider);
    if (draft.hasMedia || draft.hasCategory || draft.title.isNotEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('signalement.exit_title'.tr(), style: const TextStyle(fontFamily: 'Marianne', fontWeight: FontWeight.w700)),
          content: Text('signalement.exit_body'.tr(), style: const TextStyle(fontFamily: 'Marianne')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('signalement.exit_cancel'.tr())),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('signalement.exit_confirm'.tr(), style: const TextStyle(color: Colors.red))),
          ],
        ),
      );
      return confirm ?? false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // Keep provider alive throughout the flow
    ref.watch(signalementDraftProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: Colors.black,
        body: Column(
          children: [
            // Step indicator (hidden on camera)
            if (_currentPage > 0)
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: _StepIndicator(current: _currentPage, total: 5),
                ),
              ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeOutCubic,
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.0, 0.05),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: _buildCurrentStep(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentPage) {
      case 0:
        return CameraStep(key: const ValueKey('step0'), onNext: _next, isActive: _currentPage == 0);
      case 1:
        return CategoryStep(key: const ValueKey('step1'), onNext: _next, onBack: _back);
      case 2:
        return VoiceStep(key: const ValueKey('step2'), onNext: _next, onBack: _back);
      case 3:
        return LocationStep(key: const ValueKey('step3'), onNext: _next, onBack: _back);
      case 4:
        return SubmitStep(key: const ValueKey('step4'), onBack: _back);
      default:
        return const SizedBox.shrink();
    }
  }
}

class _StepIndicator extends StatelessWidget {
  final int current;
  final int total;

  const _StepIndicator({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        final isActive = i <= current;
        return Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            height: 3,
            margin: EdgeInsets.only(right: i < total - 1 ? 4 : 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: isActive ? const Color(0xFF1565C0) : const Color(0xFFE5E5EA),
            ),
          ),
        );
      }),
    );
  }
}
