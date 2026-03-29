import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:country_flags/country_flags.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final TextEditingController _phoneController = TextEditingController();

  void _verifyPhone() {
    if (_phoneController.text.length < 9) return;
    final phone = '+243${_phoneController.text}';
    ref.read(authProvider.notifier).sendOtp(phone);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    ref.listen<AuthState>(authProvider, (previous, next) {
      if (!mounted) return;

      final route = ModalRoute.of(context);
      final isCurrentRoute = route == null || route.isCurrent;

      if (isCurrentRoute && next.error != null && next.error != previous?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error!)),
        );
      }

      if (!isCurrentRoute) return;

      if (next.otpSent && !(previous?.otpSent ?? false)) {
        final phone = '+243${_phoneController.text}';
        context.push('/otp', extra: phone);
      }
    });

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
                'auth.login_title'.tr(),
                style: const TextStyle(
                  fontFamily: 'Marianne',
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navyDeep,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'auth.login_subtitle'.tr(),
                style: TextStyle(
                  fontFamily: 'Marianne',
                  fontSize: 16,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 48),
              
              // Phone Input Segment
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[200]!, width: 2),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                      decoration: BoxDecoration(
                        border: Border(right: BorderSide(color: Colors.grey[200]!)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: SizedBox(
                              width: 24, height: 16,
                              child: CountryFlag.fromCountryCode('CD'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            '+243', 
                            style: TextStyle(
                              fontFamily: 'Marianne', 
                              fontWeight: FontWeight.w800, 
                              fontSize: 18, 
                              color: AppColors.navyDeep
                            )
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.number,
                        maxLength: 9,
                        style: const TextStyle(
                          fontFamily: 'Marianne', 
                          fontSize: 22, 
                          fontWeight: FontWeight.w800, 
                          letterSpacing: 2.0,
                          color: AppColors.navyDeep
                        ),
                        decoration: InputDecoration(
                          hintText: 'auth.phone_hint'.tr(),
                          hintStyle: const TextStyle(color: Colors.black12),
                          counterText: '',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                        onChanged: (v) => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ),
              
              const Spacer(),
              
              // Continue Button
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _phoneController.text.length >= 9 ? AppColors.blue : Colors.grey[300],
                    disabledBackgroundColor: _phoneController.text.length >= 9 ? AppColors.blue.withValues(alpha: 0.7) : Colors.grey[300],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  onPressed: _phoneController.text.length >= 9 && !authState.isLoading ? _verifyPhone : null,
                  child: authState.isLoading 
                    ? const CupertinoActivityIndicator(color: Colors.white)
                    : Text(
                      'auth.continue_btn'.tr(),
                      style: const TextStyle(
                        fontFamily: 'Marianne',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ),
              ),
              const SizedBox(height: 16),
              
              Center(
                child: Text(
                  'auth.legal'.tr(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
