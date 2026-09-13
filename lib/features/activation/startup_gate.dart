import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../data/repositories/settings_repository.dart';
import '../../services/windows_update_service.dart';
import '../home/home_screen.dart';
import 'activation_screen.dart';
import 'olyra_license_controller.dart';

/// Decide la pantalla inicial según el estado de licencia:
///
///   checking         → splash de carga.
///   needsActivation  → pantalla de activación (bloquea el uso).
///   active           → HomeScreen (100% offline si ya fue validada).
class StartupGate extends StatelessWidget {
  const StartupGate({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<OlyraLicenseController>().state;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: switch (state) {
        OlyraLicenseState.checking => const _SplashScreen(key: ValueKey('splash')),
        OlyraLicenseState.needsActivation =>
          const ActivationScreen(key: ValueKey('activation')),
        OlyraLicenseState.active =>
          const _StartupUpdateWatcher(
            key: ValueKey('home'),
            child: HomeScreen(),
          ),
      },
    );
  }
}

/// Dispara una sola vez, tras el primer frame con licencia activa, la
/// comprobación de actualizaciones (Windows). No bloquea el arranque: si no
/// hay red o no hay versión nueva, no hace nada.
class _StartupUpdateWatcher extends StatefulWidget {
  const _StartupUpdateWatcher({super.key, required this.child});

  final Widget child;

  @override
  State<_StartupUpdateWatcher> createState() => _StartupUpdateWatcherState();
}

class _StartupUpdateWatcherState extends State<_StartupUpdateWatcher> {
  bool _triggered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_triggered) return;
    _triggered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final settings = context.read<SettingsRepository>();
      await WindowsUpdateService.checkAndPrompt(context, settings);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 48, color: scheme.primary),
            const SizedBox(height: 16),
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(AppConstants.appName,
                style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}