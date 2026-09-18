import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_constants.dart';
import '../../l10n/app_localizations.dart';
import 'report_provider.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final TextEditingController _storeController = TextEditingController();
  Timer? _storeDebounce;
  Uint8List? _bytes;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ReportProvider>();
      provider.init().then((_) {
        if (mounted && _storeController.text.isEmpty) {
          _storeController.text = provider.storeName;
        }
      });
      provider.loadProducts();
    });
  }

  @override
  void dispose() {
    _storeDebounce?.cancel();
    _storeController.dispose();
    super.dispose();
  }

  void _onStoreNameChanged(String value) {
    _storeDebounce?.cancel();
    _storeDebounce = Timer(const Duration(milliseconds: 600), () {
      context.read<ReportProvider>().setStoreName(value);
    });
  }

  Future<void> _generate() async {
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<ReportProvider>();
    setState(() => _busy = true);
    try {
      final bytes = await provider.buildReport();
      if (!mounted) return;
      setState(() => _bytes = bytes);
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            provider.error ?? AppLocalizations.of(context).reportsErrorGenerate,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final bytes = _bytes;
    if (bytes == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<ReportProvider>();
    final l10n = AppLocalizations.of(context);
    final path = await provider.saveToDevice(bytes);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          path == null ? l10n.reportsErrorSave : l10n.reportsSavedAt(path),
        ),
      ),
    );
  }

  Future<void> _share() async {
    final bytes = _bytes;
    if (bytes == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<ReportProvider>();
    final l10n = AppLocalizations.of(context);

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      // Android/iOS: guarda en almacenamiento de la app y abre la hoja de
      // compartir nativa con un content URI (share_plus → FileProvider).
      final path = await provider.saveToDevice(bytes);
      if (!mounted) return;
      if (path == null) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.reportsErrorSave)),
        );
        return;
      }
      try {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(path, mimeType: 'application/pdf')],
          ),
        );
      } catch (_) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.reportsErrorShare)),
        );
      }
    } else {
      await Printing.sharePdf(
        bytes: bytes,
        filename: provider.reportFileName(),
      );
    }
  }

  Future<void> _print() async {
    final provider = context.read<ReportProvider>();
    await Printing.layoutPdf(
      onLayout: (format) async => provider.buildForFormat(format),
      name: provider.reportFileName(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReportProvider>();
    final hasReport = _bytes != null;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.reportsTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _storeController,
              onChanged: _onStoreNameChanged,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: l10n.reportsStoreName,
                hintText: AppConstants.defaultStoreName,
                prefixIcon: const Icon(Icons.storefront_outlined),
              ),
            ),
          ),
          _StatsRow(provider: provider),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              child: _busy
                  ? const LinearProgressIndicator()
                  : FilledButton.icon(
                      onPressed: _generate,
                      icon: const Icon(Icons.download_done_outlined),
                      label: Text(l10n.reportsGenerate),
                    ),
            ),
          ),
          if (hasReport)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_alt),
                      label: Text(l10n.reportsSave),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _share,
                      icon: const Icon(Icons.share_outlined),
                      label: Text(l10n.reportsShare),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _print,
                      icon: const Icon(Icons.print_outlined),
                      label: Text(l10n.reportsPrint),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: hasReport
                ? PdfPreview(
                    build: (format) async => provider.buildForFormat(format),
                    canChangeOrientation: false,
                  )
                : const _NoReportHint(),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.provider});

  final ReportProvider provider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final low = provider.lowStockCount;

    Widget stat(String value, String label, {Color? color}) => Expanded(
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          stat('${provider.snapshot.length}', AppLocalizations.of(context).reportsProducts),
          const SizedBox(width: 8),
          stat('${provider.totalUnits}', AppLocalizations.of(context).reportsUnits),
          const SizedBox(width: 8),
          stat(
            '$low',
            AppLocalizations.of(context).reportsLowStock,
            color: low > 0 ? scheme.error : null,
          ),
        ],
      ),
    );
  }
}

class _NoReportHint extends StatelessWidget {
  const _NoReportHint();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.picture_as_pdf_outlined, size: 72, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context).reportsHint,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}