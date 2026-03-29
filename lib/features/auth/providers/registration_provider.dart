import 'package:flutter_riverpod/flutter_riverpod.dart';

class RegistrationState {
  final int currentStep;
  final String language;
  final String firstName;
  final String lastName;
  final String birthYear;
  final String phone;

  RegistrationState({
    this.currentStep = 0,
    this.language = '',
    this.firstName = '',
    this.lastName = '',
    this.birthYear = '',
    this.phone = '',
  });

  RegistrationState copyWith({
    int? currentStep,
    String? language,
    String? firstName,
    String? lastName,
    String? birthYear,
    String? phone,
  }) {
    return RegistrationState(
      currentStep: currentStep ?? this.currentStep,
      language: language ?? this.language,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      birthYear: birthYear ?? this.birthYear,
      phone: phone ?? this.phone,
    );
  }
}

class RegistrationNotifier extends StateNotifier<RegistrationState> {
  RegistrationNotifier() : super(RegistrationState());

  void setLanguage(String lang) => state = state.copyWith(language: lang);
  void setFirstName(String name) => state = state.copyWith(firstName: name);
  void setLastName(String name) => state = state.copyWith(lastName: name);
  void setBirthYear(String year) => state = state.copyWith(birthYear: year);
  void setPhone(String phone) => state = state.copyWith(phone: phone);

  void nextStep() {
    if (state.currentStep < 4) { // Max 4 index (0 to 4 = 5 steps)
      state = state.copyWith(currentStep: state.currentStep + 1);
    }
  }

  void previousStep() {
    if (state.currentStep > 0) {
      state = state.copyWith(currentStep: state.currentStep - 1);
    }
  }
}

final registrationProvider = StateNotifierProvider<RegistrationNotifier, RegistrationState>((ref) {
  return RegistrationNotifier();
});
