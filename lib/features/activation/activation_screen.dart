import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import 'olyra_license_controller.dart';

/// Pantalla inicial de activación: se muestra cuando no hay una licencia
/// local válida. Un solo uso online; después la app valida offline.
class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _licenseKeyController = TextEditingController();
  bool _copied = false;

  @override
  void dispose() {
    _licenseKeyController.dispose();
    super.dispose();
  }

  Future<void> _activate(OlyraLicenseController license) async {
    FocusScope.of(context).unfocus();
    await license.activate(_licenseKeyController.text);
  }

  @override
  Widget build(BuildContext context) {
    final license = context.watch<OlyraLicenseController>();
    final scheme = Theme.of(context).colorScheme;
    final hardwareId = license.hardwareId ?? '…';

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: scheme.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 48,
                      color: scheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      AppConstants.appName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Activa tu copia del sistema',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Ingresa el License Key que recibiste al adquirir el '
                      'sistema. La activación se hace una sola vez con '
                      'internet; a partir de ahí la licencia se valida '
                      'localmente sin conexión.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _hardwareCard(context, hardwareId),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _licenseKeyController,
                      autofocus: true,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _activate(license),
                      decoration: const InputDecoration(
                        labelText: 'License Key de activación',
                        hintText: 'XXXX-XXXX-XXXX-XXXX',
                        prefixIcon: Icon(Icons.key_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (license.activationError != null) ...[
                      const SizedBox(height: 12),
                      Card(
                        color: scheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            license.activationError!,
                            style: TextStyle(color: scheme.onErrorContainer),
                          ),
                        ),
                      ),
                    ],
                    if (license.lastMessage.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Card(
                        color: scheme.secondaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            license.lastMessage,
                            style:
                                TextStyle(color: scheme.onSecondaryContainer),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: license.activating
                          ? null
                          : () => _activate(license),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: license.activating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Activar'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.offline_pin_outlined,
                            size: 14, color: scheme.outline),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'La validación de la licencia ocurre sin internet '
                            'en cada apertura.',
                            style: TextStyle(
                                fontSize: 12, color: scheme.outline),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _hardwareCard(BuildContext context, String hardwareId) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.desktop_windows_outlined, size: 20, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Identificador de este equipo',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hardwareId,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: _copied ? 'Copiado' : 'Copiar identificador',
            icon: Icon(
              _copied ? Icons.check : Icons.copy,
              size: 18,
              color: scheme.primary,
            ),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: hardwareId));
              if (!mounted) return;
              setState(() => _copied = true);
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) setState(() => _copied = false);
              });
            },
          ),
        ],
      ),
    );
  }
}