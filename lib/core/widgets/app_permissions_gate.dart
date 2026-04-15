import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:etoile_bleue_mobile/core/providers/app_permissions_provider.dart';
import 'package:etoile_bleue_mobile/core/providers/call_state_provider.dart';
import 'package:etoile_bleue_mobile/core/services/app_permissions_service.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';

/// Bloque toute l'app (login inclus) tant que les autorisations critiques ne sont pas accordées.
/// Exception : pendant un appel SOS (callState.isInCall) pour permettre le décroché.
class AppPermissionsGate extends ConsumerStatefulWidget {
  final Widget child;

  const AppPermissionsGate({super.key, required this.child});

  @override
  ConsumerState<AppPermissionsGate> createState() => _AppPermissionsGateState();
}

class _AppPermissionsGateState extends ConsumerState<AppPermissionsGate> with WidgetsBindingObserver {
  bool _busy = false;
  GoRouter? _goRouter;
  VoidCallback? _onRouteChanged;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _attachRouteListener());
  }

  void _attachRouteListener() {
    if (!mounted) return;
    final router = GoRouter.maybeOf(context);
    if (router == null) return;

    _goRouter = router;
    _onRouteChanged = () {
      if (!mounted) return;
      ref.read(appPermissionsProvider.notifier).refresh();
    };
    router.routerDelegate.addListener(_onRouteChanged!);
  }

  @override
  void dispose() {
    final r = _goRouter;
    final cb = _onRouteChanged;
    if (r != null && cb != null) {
      r.routerDelegate.removeListener(cb);
    }
    _goRouter = null;
    _onRouteChanged = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(appPermissionsProvider.notifier).refresh();
    }
  }

  Future<void> _exec(Future<Object?> future) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await future;
      await ref.read(appPermissionsProvider.notifier).refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(appPermissionsProvider);
    final callState = ref.watch(callStateProvider);

    if (callState.isInCall) {
      return widget.child;
    }

    return async.when(
      loading: () => Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          const ColoredBox(
            color: Color(0xFFF5F5F7),
            child: Center(child: CupertinoActivityIndicator(radius: 16)),
          ),
        ],
      ),
      error: (_, _) => widget.child,
      data: (snap) {
        if (snap.allGranted) {
          return widget.child;
        }

        return PopScope(
          canPop: false,
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.child,
              Positioned.fill(
                child: Material(
                  color: AppColors.background.withValues(alpha: 0.97),
                  child: SafeArea(
                    child: AbsorbPointer(
                      absorbing: _busy,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        child: Column(
                          children: [
                            const SizedBox(height: 8),
                            Icon(CupertinoIcons.lock_shield_fill, size: 48, color: AppColors.blue),
                            const SizedBox(height: 16),
                            Text(
                              'permissions_gate.title'.tr(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'Marianne',
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: AppColors.navyDeep,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'permissions_gate.subtitle'.tr(),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.35,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 24),
                            Expanded(
                              child: SingleChildScrollView(
                                child: Column(
                                  children: [
                                    _PermissionRow(
                                      title: 'permissions_gate.location'.tr(),
                                      subtitle: snap.locationServiceEnabled
                                          ? 'permissions_gate.location_desc'.tr()
                                          : 'permissions_gate.location_service_disabled'.tr(),
                                      value: snap.locationGranted,
                                      onChanged: snap.locationGranted
                                          ? null
                                          : (_) => _exec(AppPermissionsService.requestLocation()),
                                      onOpenSettings: (!snap.locationGranted &&
                                              snap.locationPermission == LocationPermission.deniedForever)
                                          ? () => _exec(AppPermissionsService.openSystemSettings())
                                          : null,
                                    ),
                                    _PermissionRow(
                                      title: 'permissions_gate.microphone'.tr(),
                                      subtitle: 'permissions_gate.microphone_desc'.tr(),
                                      value: snap.microphone == PermissionStatus.granted,
                                      onChanged: snap.microphone == PermissionStatus.granted
                                          ? null
                                          : (_) => _exec(AppPermissionsService.requestMicrophone()),
                                      onOpenSettings: snap.microphone == PermissionStatus.permanentlyDenied
                                          ? () => _exec(AppPermissionsService.openSystemSettings())
                                          : null,
                                    ),
                                    _PermissionRow(
                                      title: 'permissions_gate.camera'.tr(),
                                      subtitle: 'permissions_gate.camera_desc'.tr(),
                                      value: snap.camera == PermissionStatus.granted,
                                      onChanged: snap.camera == PermissionStatus.granted
                                          ? null
                                          : (_) => _exec(AppPermissionsService.requestCamera()),
                                      onOpenSettings: snap.camera == PermissionStatus.permanentlyDenied
                                          ? () => _exec(AppPermissionsService.openSystemSettings())
                                          : null,
                                    ),
                                    _PermissionRow(
                                      title: 'permissions_gate.notifications'.tr(),
                                      subtitle: 'permissions_gate.notifications_desc'.tr(),
                                      value: snap.notification == PermissionStatus.granted,
                                      onChanged: snap.notification == PermissionStatus.granted
                                          ? null
                                          : (_) => _exec(AppPermissionsService.requestNotification()),
                                      onOpenSettings: snap.notification == PermissionStatus.permanentlyDenied
                                          ? () => _exec(AppPermissionsService.openSystemSettings())
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _busy ? null : () => _exec(AppPermissionsService.openSystemSettings()),
                              icon: const Icon(CupertinoIcons.gear, size: 18),
                              label: Text('permissions_gate.open_settings'.tr()),
                            ),
                            if (_busy)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 8),
                                child: CupertinoActivityIndicator(),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final void Function(bool)? onChanged;
  final VoidCallback? onOpenSettings;

  const _PermissionRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600], height: 1.2)),
                  if (onOpenSettings != null) ...[
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: onOpenSettings,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text('permissions_gate.open_settings'.tr()),
                    ),
                  ],
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              activeThumbColor: AppColors.blue,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
