import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinput/pinput.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/dynamic_island_notification.dart';
import '../providers/auth_provider.dart';

class OtpPage extends ConsumerStatefulWidget {
  final String phoneNumber;
  const OtpPage({super.key, required this.phoneNumber});

  @override
  ConsumerState<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends ConsumerState<OtpPage> {
  bool _isLoading = false;
  final TextEditingController _pinController = TextEditingController();
  
  Timer? _timer;
  int _countdown = 60;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pinController.dispose();
    super.dispose();
  }

  void _startTimer() {
    setState(() => _countdown = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_countdown > 0) {
        setState(() => _countdown--);
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _verifyCode(String code) async {
    setState(() => _isLoading = true);
    
    final success = await ref.read(authProvider.notifier).verifyOtp(code);
    
    if (mounted) {
      if (success) {
        DynamicIslandNotification.show(
          context,
          message: 'Numéro vérifié', // Message de confirmation rapide
          icon: CupertinoIcons.checkmark_seal_fill,
        );

        // Laisser 2 secondes à l'utilisateur pour voir la belle notification
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() => _isLoading = false);
            final isNewUser = ref.read(authProvider).isNewUser;
            if (isNewUser) {
              context.go('/register');
            } else {
              context.go('/home'); 
            }
          }
        });
      } else {
        setState(() => _isLoading = false);
        // Utiliser l'erreur détaillée générée par le provider
        final errorMessage = ref.read(authProvider).error ?? 'auth.invalid_code'.tr();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultPinTheme = PinTheme(
      width: 60,
      height: 70,
      textStyle: const TextStyle(fontSize: 28, color: AppColors.navyDeep, fontWeight: FontWeight.w800, fontFamily: 'Marianne'),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border.all(color: Colors.grey[200]!, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
    );

    final focusedPinTheme = defaultPinTheme.copyDecorationWith(
      border: Border.all(color: AppColors.blue, width: 2),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back, color: Colors.black),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text(
                'auth.otp_title'.tr(),
                style: const TextStyle(
                  fontFamily: 'Marianne',
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navyDeep,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 12),
              RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontFamily: 'Marianne',
                    fontSize: 16,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                  children: [
                    TextSpan(text: '${'auth.otp_subtitle'.tr()} '),
                    TextSpan(
                      text: widget.phoneNumber,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.navyDeep),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 48),
              
              Center(
                child: Pinput(
                  controller: _pinController,
                  length: 6,
                  defaultPinTheme: defaultPinTheme,
                  focusedPinTheme: focusedPinTheme,
                  cursor: Container(
                    width: 2,
                    height: 30,
                    color: AppColors.blue,
                  ),
                  onCompleted: (pin) => _verifyCode(pin),
                ),
              ),
              
              const Spacer(),
              
              if (_isLoading)
                const Center(child: CupertinoActivityIndicator(radius: 16))
              else
                Center(
                  child: TextButton(
                    onPressed: _countdown == 0 ? () {
                      _startTimer();
                      ref.read(authProvider.notifier).sendOtp(widget.phoneNumber);
                    } : null,
                    child: Text(
                      _countdown > 0 ? 'auth.resend_btn_wait'.tr(args: [_countdown.toString()]) : 'auth.resend_btn'.tr(),
                      style: TextStyle(
                        fontFamily: 'Marianne',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _countdown > 0 ? Colors.grey[400] : AppColors.blue,
                      ),
                    ),
                  ),
                ),
              
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
