import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:etoile_bleue_mobile/core/services/app_permissions_service.dart';

/// État des autorisations critiques ; appeler [refresh] au retour des réglages système.
class AppPermissionsNotifier extends AsyncNotifier<AppPermissionsSnapshot> {
  @override
  Future<AppPermissionsSnapshot> build() async {
    return AppPermissionsService.checkAll();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(AppPermissionsService.checkAll);
  }
}

final appPermissionsProvider =
    AsyncNotifierProvider<AppPermissionsNotifier, AppPermissionsSnapshot>(AppPermissionsNotifier.new);
