import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../license/license_service.dart';
import 'backup_service.dart';
import 'cloud_sync_manager.dart';

/// Abre el diálogo de sincronización/respaldo de la nube (BodegaFlow POS).
Future<void> showCloudSyncPanel(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const CloudSyncPanel(),
  );
}

/// Panel de estado y acciones de la nube: licencia por hardware, sincronización
/// offline-first y respaldos comprimidos.
class CloudSyncPanel extends StatefulWidget {
  const CloudSyncPanel({super.key});

  @override
  State<CloudSyncPanel> createState() => _CloudSyncPanelState();
}

class _CloudSyncPanelState extends State<CloudSyncPanel> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _signingIn = false;
  bool _busyBackup = false;
  String? _lastMessage;
  bool _isError = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final license = context.read<LicenseService>();
    setState(() {
      _signingIn = true;
      _isError = false;
      _lastMessage = null;
    });
    try {
      await license.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      _passwordController.clear();
      _lastMessage = 'Sesión iniciada.';
      _isError = false;
    } catch (error) {
      _lastMessage = 'No se pudo iniciar sesión: $error';
      _isError = true;
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _validate() async {
    final license = context.read<LicenseService>();
    setState(() {
      _isError = false;
      _lastMessage = 'Validando licencia…';
    });
    try {
      await license.refresh();
      _lastMessage = switch (license.status) {
        LicenseStatus.active => 'Licencia válida en este equipo.',
        LicenseStatus.invalid => 'Licencia inválida o expirada en este equipo.',
        LicenseStatus.needsLogin => 'Inicia sesión para validar la licencia.',
        _ => 'No hay nube configurada.',
      };
      _isError = license.status != LicenseStatus.active;
    } catch (error) {
      _lastMessage = 'Error al validar: $error';
      _isError = true;
    }
    if (mounted) setState(() {});
  }

  Future<void> _syncNow() async {
    final sync = context.read<CloudSyncManager>();
    setState(() {
      _isError = false;
      _lastMessage = 'Sincronizando…';
    });
    try {
      final result = await sync.maybeSyncNow();
      _lastMessage = result == null
          ? 'Sincronización disparada.'
          : result.describe();
      _isError = false;
    } catch (error) {
      _lastMessage = 'Error de sincronización: $error';
      _isError = true;
    }
    if (mounted) setState(() {});
  }

  Future<void> _backup() async {
    final backup = context.read<BackupService>();
    setState(() {
      _busyBackup = true;
      _isError = false;
      _lastMessage = 'Generando respaldo…';
    });
    try {
      final path = await backup.createBackup();
      _lastMessage = 'Respaldo subido: $path';
      _isError = false;
    } catch (error) {
      _lastMessage = 'No se pudo respaldar: $error';
      _isError = true;
    } finally {
      if (mounted) setState(() => _busyBackup = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final license = context.watch<LicenseService>();
    final sync = context.watch<CloudSyncManager>();
    final backup = context.watch<BackupService>();

    return AlertDialog(
      title: const Text('Sincronización y respaldo'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _licenseSection(license),
              const SizedBox(height: 12),
              _syncSection(sync),
              const SizedBox(height: 12),
              _backupSection(backup),
              if (_lastMessage != null) ...[
                const SizedBox(height: 12),
                Card(
                  color: _isError
                      ? Theme.of(context).colorScheme.errorContainer
                      : Theme.of(context).colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(_lastMessage!, style: const TextStyle(fontSize: 13)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }

  Widget _licenseSection(LicenseService license) {
    final status = license.status;
    final (icon, color, text) = switch (status) {
      LicenseStatus.unconfigured => (
          Icons.cloud_off,
          Theme.of(context).colorScheme.outline,
          'Nube desactivada (modo 100% local).',
        ),
      LicenseStatus.needsLogin => (
          Icons.login,
          Theme.of(context).colorScheme.tertiary,
          'Inicia sesión para vincular la licencia.',
        ),
      LicenseStatus.loading => (
          Icons.hourglass_top,
          Theme.of(context).colorScheme.primary,
          'Validando dispositivo…',
        ),
      LicenseStatus.active => (
          Icons.verified_user_outlined,
          Theme.of(context).colorScheme.primary,
          'Licencia activa.',
        ),
      LicenseStatus.invalid => (
          Icons.gpp_bad_outlined,
          Theme.of(context).colorScheme.error,
          'Licencia inválida o expirada: ventas bloqueadas.',
        ),
    };

    return _Section(
      title: 'Licencia del equipo',
      icon: Icons.key_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text,
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          if (license.hardwareId.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Hardware: ${license.hardwareId}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          if (status == LicenseStatus.needsLogin) _signInForm(),
          if (status != LicenseStatus.needsLogin)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _validate,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Revalidar'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _signInForm() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Email',
              isDense: true,
              prefixIcon: Icon(Icons.mail_outline),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _passwordController,
            obscureText: true,
            onSubmitted: (_) => _signIn(),
            decoration: const InputDecoration(
              labelText: 'Contraseña',
              isDense: true,
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: _signingIn ? null : _signIn,
              child: _signingIn
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Iniciar sesión'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _syncSection(CloudSyncManager sync) {
    final (icon, color, text) = switch (sync.state) {
      CloudSyncState.unconfigured => (
          Icons.cloud_off,
          Theme.of(context).colorScheme.outline,
          'Sin configurar.',
        ),
      CloudSyncState.needsLogin => (
          Icons.login,
          Theme.of(context).colorScheme.tertiary,
          'Se requiere sesión.',
        ),
      CloudSyncState.idle => (
          Icons.cloud_done_outlined,
          Theme.of(context).colorScheme.primary,
          'Al día.',
        ),
      CloudSyncState.syncing => (
          Icons.sync,
          Theme.of(context).colorScheme.primary,
          'Sincronizando…',
        ),
      CloudSyncState.error => (
          Icons.cloud_off_outlined,
          Theme.of(context).colorScheme.error,
          'Error — reintento automático programado.',
        ),
    };

    return _Section(
      title: 'Sincronización',
      icon: Icons.cloud_sync_outlined,
      actions: [
        TextButton.icon(
          onPressed: () => _syncNow(),
          icon: const Icon(Icons.sync, size: 18),
          label: const Text('Sincronizar ahora'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
            ],
          ),
          if (sync.lastError != null && sync.state == CloudSyncState.error)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${sync.lastError}',
                  style: TextStyle(
                      fontSize: 12, color: Theme.of(context).colorScheme.error)),
            ),
          if (sync.lastSuccess != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Último sync: ${_fmt(sync.lastSuccess)}',
                  style: const TextStyle(fontSize: 12)),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('${sync.pendingSales} venta(s) pendientes en local',
                style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _backupSection(BackupService backup) {
    return _Section(
      title: 'Respaldo de la bodega',
      icon: Icons.architecture_outlined,
      actions: [
        TextButton.icon(
          onPressed: _busyBackup || backup.running ? null : _backup,
          icon: const Icon(Icons.upload_file_outlined, size: 18),
          label: const Text('Subir respaldo'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (backup.lastBackupAt != null)
            Text('Último: ${_fmt(backup.lastBackupAt)} (${backup.lastBackupPath})',
                style: const TextStyle(fontSize: 12)),
          if (backup.running)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Generando y subiendo…',
                  style: TextStyle(fontSize: 12)),
            ),
          if (backup.lastError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${backup.lastError}',
                  style: TextStyle(
                      fontSize: 12, color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
    );
  }

  static String _fmt(DateTime? value) {
    if (value == null) return '-';
    final local = value.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year} $hh:$mm';
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
    this.actions = const [],
  });

  final String title;
  final IconData icon;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              if (actions.isNotEmpty) ...actions,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}