import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';

/// Notifié après chaque [setAppLocale] pour que [GoRouter.refreshListenable]
/// reconstruise les écrans avec les nouvelles chaînes `.tr()` (sinon MaterialApp
/// peut garder la même locale `fr_FR` pour ln/kg/lu et ne pas rafraîchir l’UI).
final appLocaleRefreshNotifier = ValueNotifier<int>(0);

Future<void> setAppLocale(BuildContext context, Locale locale) async {
  await context.setLocale(locale);
  appLocaleRefreshNotifier.value++;
}
