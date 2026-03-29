import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/registration_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final PageController _pageController = PageController();
  
  final _fnCtrl = TextEditingController();
  final _lnCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();

  final List<String> _languages = ['Français', 'Anglais', 'Lingala', 'Swahili', 'Kikongo', 'Tshiluba'];

  void _nextStep() {
    final state = ref.read(registrationProvider);
    if (state.currentStep < 3) {
      ref.read(registrationProvider.notifier).nextStep();
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      // Final Step -> Save Profile -> Home
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      final phone = supabase.auth.currentUser?.phone ?? state.phone;
      if (userId != null) {
        supabase.from('users_directory').upsert({
          'auth_user_id': userId,
          'phone': phone,
          'first_name': state.firstName,
          'last_name': state.lastName,
          'language': state.language,
          'birth_year': int.tryParse(state.birthYear) ?? 2000,
          'status': 'online',
          'last_seen_at': DateTime.now().toIso8601String(),
          'created_at': DateTime.now().toIso8601String(),
        }).then((_) {
          if (mounted) context.go('/home');
        }).catchError((e) {
          if (mounted) context.go('/home');
        });
      } else {
        if (mounted) context.go('/home');
      }
    }
  }

  void _prevStep() {
    final state = ref.read(registrationProvider);
    if (state.currentStep > 0) {
      ref.read(registrationProvider.notifier).previousStep();
      _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(registrationProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back, color: Colors.black),
          onPressed: _prevStep,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Progress Indication
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Row(
                children: List.generate(4, (index) {
                  return Expanded(
                    child: Container(
                      margin: EdgeInsets.only(right: index == 3 ? 0 : 8),
                      height: 4,
                      decoration: BoxDecoration(
                        color: index <= state.currentStep ? AppColors.blue : Colors.grey[200],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 32),
            
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildLanguageStep(state),
                  _buildInputStep('register.firstname_title'.tr(), 'register.firstname_label'.tr(), _fnCtrl, (v) => ref.read(registrationProvider.notifier).setFirstName(v), state.firstName.isNotEmpty),
                  _buildInputStep('register.lastname_title'.tr(), 'register.lastname_label'.tr(), _lnCtrl, (v) => ref.read(registrationProvider.notifier).setLastName(v), state.lastName.isNotEmpty),
                  _buildInputStep('register.birth_title'.tr(), 'register.birth_hint'.tr(), _yearCtrl, (v) => ref.read(registrationProvider.notifier).setBirthYear(v), state.birthYear.length == 4, keyboardType: TextInputType.number),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeLocale(String lang) async {
    if (!mounted) return;
    switch (lang) {
      case 'Anglais': await context.setLocale(const Locale('en', 'US')); break;
      case 'Swahili': await context.setLocale(const Locale('sw', 'KE')); break;
      case 'Lingala': await context.setLocale(const Locale('ln', 'CD')); break;
      case 'Kikongo': await context.setLocale(const Locale('kg', 'CD')); break;
      case 'Tshiluba': await context.setLocale(const Locale('lu', 'CD')); break;
      default: await context.setLocale(const Locale('fr', 'FR'));
    }
  }

  Widget _buildLanguageStep(RegistrationState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('register.lang_title'.tr(), style: const TextStyle(fontFamily: 'Marianne', fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.navyDeep, letterSpacing: -1)),
          const SizedBox(height: 12),
          Text('register.lang_subtitle'.tr(), style: TextStyle(fontFamily: 'Marianne', fontSize: 16, color: Colors.grey[600], height: 1.4)),
          const SizedBox(height: 40),
          Expanded(
            child: ListView.separated(
              itemCount: _languages.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final lang = _languages[index];
                final isSelected = state.language == lang;
                return InkWell(
                  onTap: () async {
                    await _changeLocale(lang);
                    ref.read(registrationProvider.notifier).setLanguage(lang);
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.blue.withValues(alpha: 0.1) : Colors.grey[50],
                      border: Border.all(color: isSelected ? AppColors.blue : Colors.grey[200]!, width: 2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(lang, style: TextStyle(fontSize: 18, fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, color: isSelected ? AppColors.blue : AppColors.navyDeep)),
                        if (isSelected) const Icon(CupertinoIcons.checkmark_alt_circle_fill, color: AppColors.blue),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          _buildContinueButton(state.language.isNotEmpty),
        ],
      ),
    );
  }

  Widget _buildInputStep(String title, String hint, TextEditingController ctrl, Function(String) onChanged, bool isValid, {TextInputType keyboardType = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontFamily: 'Marianne', fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.navyDeep, letterSpacing: -1)),
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[200]!, width: 2)),
            child: TextField(
              controller: ctrl,
              keyboardType: keyboardType,
              style: const TextStyle(fontFamily: 'Marianne', fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.navyDeep),
              decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: Colors.black12), border: InputBorder.none),
              onChanged: (v) {
                onChanged(v);
                setState(() {});
              },
            ),
          ),
          const Spacer(),
          _buildContinueButton(isValid),
        ],
      ),
    );
  }



  Widget _buildContinueButton(bool isValid) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: SizedBox(
        width: double.infinity,
        height: 60,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isValid ? AppColors.blue : Colors.grey[300],
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
          onPressed: isValid ? _nextStep : null,
          child: Text('auth.continue_btn'.tr(), style: const TextStyle(fontFamily: 'Marianne', fontSize: 18, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
