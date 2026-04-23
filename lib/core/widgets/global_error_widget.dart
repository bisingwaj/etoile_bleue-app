import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';

class GlobalErrorWidget extends StatelessWidget {
  final FlutterErrorDetails? details;
  final dynamic error;

  const GlobalErrorWidget({
    super.key,
    this.details,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  CupertinoIcons.exclamationmark_shield_fill,
                  color: AppColors.red,
                  size: 80,
                ),
                const SizedBox(height: 32),
                Text(
                  'errors.unexpected_error'.tr(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navyDeep,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Une erreur critique est survenue qui nécessite le redémarrage de l\'application. Nous nous excusons pour ce désagrément.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 48),
                ElevatedButton(
                  onPressed: () {
                    // There's no easy way to "restart" the entire Flutter engine 
                    // from within a widget, so we usually suggest closing the app or 
                    // redirecting to splash.
                    // For now, let's just provide a way to clear the error.
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navyDeep,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    'errors.reconnect'.tr(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (details != null || error != null) ...[
                  const SizedBox(height: 32),
                  TextButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Détails techniques'),
                          content: SingleChildScrollView(
                            child: Text(
                              details?.exceptionAsString() ?? error.toString(),
                              style: const TextStyle(fontSize: 12, fontFamily: 'Courier'),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Fermer'),
                            )
                          ],
                        ),
                      );
                    },
                    child: Text(
                      'Voir les détails techniques',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
