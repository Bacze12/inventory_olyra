import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../activation/olyra_license_controller.dart';
import 'olyra_cloud_sync.dart';

/// Abre el diálogo de sincronización/respaldo de la nube (olyra.cl).
Future<void> showCloudSyncPanel(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const CloudSyncPanel(),
  );
}

/// Panel de estado y acciones de la nube Olyra: usa las credenciales de la
/// activación (`license_key` + `user_app_id`) para revalidar y hacer respaldo
/// (ventas + movimientos) contra `olyra.cl/api/v1/pos/sync`.
class CloudSyncPanel extends StatefulWidget {
  const CloudSyncPanel({super.key});

  @override
  State<CloudSyncPanel> createState() => _CloudSyncPanelState();
}

class _CloudSyncPanelState extends State<CloudSyncPanel> {
  String? _lastMessage;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    // Al abrir el panel se releen los pendientes DE LA BD local
    // (`SELECT * FROM sales WHERE synced = 0`), no el snapshot del arranque:
    // si se cobraron ventas después de iniciar la app, acá ya se cuentan.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<OlyraCloudSync>().refreshPending();
    });
  }

  Future<void> _validate() async {
    final cloud = context.read<OlyraCloudSync>();
    setState(() {
      _isError = false;
      _lastMessage = 'Validando con olyra.cl…';
    });
    final ok = await cloud.validate();
    if (!mounted) return;
    setState(() {
      if (ok) {
        _lastMessage = 'Licencia confirmada: nube activa y sincronizada.';
        _isError = false;
      } else {
        final error = cloud.lastError;
        _lastMessage = error == null
            ? 'La licencia no fue confirmada en este equipo.'
            : 'No se pudo validar: $error';
        _isError = true;
      }
    });
  }

  Future<void> _syncNow() async {
    final cloud = context.read<OlyraCloudSync>();
    setState(() {
      _isError = false;
      _lastMessage = 'Sincronizando con la nube…';
    });
    try {
      final result = await cloud.syncNow();
      if (!mounted) return;
      setState(() {
        _lastMessage = result.describe();
        _isError = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _lastMessage = 'No se pudo sincronizar: $error';
        _isError = true;
      });
    }
  }

  Future<void> _backup() async {
    final cloud = context.read<OlyraCloudSync>();
    setState(() {
      _isError = false;
      _lastMessage = 'Preparando respaldo de catálogo, ventas y movimientos…';
    });
    try {
      // 1) Respaldo FÍSICO: captura el archivo `.sqlite` real de la app.
      final localBackup = await cloud.createLocalBackup();
      // 2) Respaldo en nube: payload JSON (ventas + movimientos + catálogo).
      final result = await cloud.syncNow();
      if (!mounted) return;
      setState(() {
        _lastMessage = result.hasChanges
            ? 'Respaldo local · ${localBackup.path} · subido a la nube: '
                '${result.describe()}'
            : 'Respaldo al día en ${localBackup.path}: no hay cambios '
                'pendientes en la nube.';
        _isError = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _lastMessage = 'No se pudo respaldar: $error';
        _isError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<OlyraCloudSync>();
    final license = context.watch<OlyraLicenseController>();

    return AlertDialog(
      title: const Text('Nube y respaldo'),
      // scrollable: el contenido (3 secciones + mensaje) puede exceder la
      // altura de la ventana; con este flag AlertDialog lo hace scrolleable y
      // evita el RenderFlex overflow (franja gris) en pantallas pequeñas.
      scrollable: true,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _guard(() => _connectionSection(context, cloud, license)),
            const SizedBox(height: 12),
            _guard(() => _syncSection(context, cloud)),
            const SizedBox(height: 12),
            _guard(() => _backupSection(context, cloud)),
            if (_lastMessage != null) ...[
              const SizedBox(height: 12),
              Card(
                color: _isError
                    ? Theme.of(context).colorScheme.errorContainer
                    : Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(_lastMessage!,
                      style: const TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ],
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

  /// Fallback visual: si una sección falla (p. ej. la nube aún no termina de
  /// inicializarse), se muestra un aviso discreto en vez de romper el diálogo.
  Widget _guard(Widget Function() builder) {
    try {
      return builder();
    } catch (_) {
      return const _Section(
        title: 'Nube',
        icon: Icons.cloud_off_outlined,
        child: Text(
          'El estado de la nube está inicializándose. Intenta de nuevo en un momento.',
          style: TextStyle(fontSize: 13),
        ),
      );
    }
  }

  Widget _connectionSection(
    BuildContext context,
    OlyraCloudSync cloud,
    OlyraLicenseController license,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, text) = switch (cloud.state) {
      OlyraCloudState.unconfigured => (
          Icons.cloud_sync_outlined,
          scheme.outline,
          'Nube lista para vincular: pulsa "Revalidar".',
        ),
      OlyraCloudState.needsActivation => (
          Icons.gpp_bad_outlined,
          scheme.error,
          'Licencia no activa: activa el equipo para usar la nube.',
        ),
      OlyraCloudState.validating => (
          Icons.hourglass_top,
          scheme.primary,
          'Validando con olyra.cl…',
        ),
      OlyraCloudState.syncing => (
          Icons.sync,
          scheme.primary,
          'Sincronizando con la nube…',
        ),
      OlyraCloudState.active => (
          Icons.cloud_done_outlined,
          scheme.primary,
          'Nube Activa · Sincronizado',
        ),
      OlyraCloudState.error => (
          Icons.cloud_off_outlined,
          scheme.error,
          'Error al conectar la nube.',
        ),
    };

    return _Section(
      title: 'Conexión a la nube',
      icon: Icons.key_outlined,
      actions: [
        TextButton.icon(
          onPressed: _validate,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Revalidar'),
        ),
      ],
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
          if (cloud.lastError != null && cloud.state == OlyraCloudState.error)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${cloud.lastError}',
                  style: TextStyle(fontSize: 12, color: scheme.error)),
            ),
          if (license.hardwareId != null && license.hardwareId!.isNotEmpty)
            _infoRow('Hardware', license.hardwareId!),
          if (cloud.deviceName.isNotEmpty) _infoRow('Equipo', cloud.deviceName),
          if (cloud.userAppId.isNotEmpty)
            _infoRow('Cuenta (user_app_id)', cloud.userAppId),
        ],
      ),
    );
  }

  Widget _syncSection(BuildContext context, OlyraCloudSync cloud) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, text) = switch (cloud.state) {
      OlyraCloudState.unconfigured => (
          Icons.cloud_off,
          scheme.outline,
          'Sin validar todavía.',
        ),
      OlyraCloudState.needsActivation => (
          Icons.gpp_bad_outlined,
          scheme.error,
          'Licencia no activa.',
        ),
      OlyraCloudState.validating => (
          Icons.hourglass_top,
          scheme.primary,
          'Validando…',
        ),
      OlyraCloudState.syncing => (
          Icons.sync,
          scheme.primary,
          'Sincronizando…',
        ),
      OlyraCloudState.active => (
          Icons.cloud_done_outlined,
          scheme.primary,
          'Nube Activa · Sincronizado',
        ),
      OlyraCloudState.error => (
          Icons.cloud_off_outlined,
          scheme.error,
          'Error — reintenta.',
        ),
    };

    return _Section(
      title: 'Sincronización',
      icon: Icons.cloud_sync_outlined,
      actions: [
        TextButton.icon(
          onPressed: _syncNow,
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
          if (cloud.lastSync != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Último sync: ${_fmt(cloud.lastSync)}',
                  style: const TextStyle(fontSize: 12)),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
                '${cloud.pendingSales} venta(s) · '
                '${cloud.pendingShifts} turno(s) pendientes · '
                '${cloud.catalogSize} producto(s) en catálogo',
                style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _backupSection(BuildContext context, OlyraCloudSync cloud) {
    return _Section(
      title: 'Respaldo de la bodega',
      icon: Icons.architecture_outlined,
      actions: [
        TextButton.icon(
          onPressed: cloud.state == OlyraCloudState.syncing
              ? null
              : _backup,
          icon: const Icon(Icons.upload_file_outlined, size: 18),
          label: const Text('Subir respaldo'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cloud.lastSync != null)
            Text(
              'Último respaldo: ${_fmt(cloud.lastSync)} '
              '(${cloud.lastProductsPushed} producto(s) · '
              '${cloud.lastSalesPushed} venta(s) · '
              '${cloud.lastShiftsPushed} turno(s) · '
              '${cloud.lastMovementsPushed} movimiento(s))',
              style: const TextStyle(fontSize: 12),
            )
          else
            const Text(
              'Sube el catálogo completo, las ventas y los movimientos a la nube olyra.cl.',
              style: TextStyle(fontSize: 12),
            ),
          if (cloud.lastLocalBackupPath != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Archivo local: ${cloud.lastLocalBackupPath} '
                '(${cloud.lastLocalBackupSize} bytes)',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          if (cloud.state == OlyraCloudState.syncing)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Generando y subiendo…',
                  style: TextStyle(fontSize: 12)),
            ),
          if (cloud.lastError != null && cloud.state == OlyraCloudState.error)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${cloud.lastError}',
                  style: TextStyle(
                      fontSize: 12, color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600)),
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