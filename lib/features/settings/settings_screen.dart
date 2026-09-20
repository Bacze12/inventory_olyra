import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/i18n/app_strings.dart';
import 'language_provider.dart';

typedef LinkOpener = Future<void> Function(Uri url);

/// Panel de ajustes con el selector de idioma (español / inglés) y un acceso
/// a los enlaces de privacidad y términos.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.linkOpener});

  /// Inyectable para abrir enlaces; por defecto usa [launchUrl]. Permite
  /// verificar en tests qué URL se abre.
  final LinkOpener? linkOpener;

  Future<void> _open(String url) async {
    final opener = linkOpener;
    if (opener != null) {
      await opener(Uri.parse(url));
      return;
    }
    await launchUrl(Uri.parse(url));
  }

  @override
  Widget build(BuildContext context) {
    final language = context.watch<LanguageProvider>();
    final scheme = Theme.of(context).colorScheme;

    String tr(String key) => AppStrings.translate(language.languageCode, key);

    return Scaffold(
      appBar: AppBar(title: Text(tr(AppStrings.settingsTitle))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            tr(AppStrings.settingsLanguage),
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _LanguageTile(
                  code: AppStrings.es,
                  label: 'Español',
                  selected: language.languageCode == AppStrings.es,
                  onTap: () => language.setLanguage(AppStrings.es),
                ),
                Divider(height: 1, color: scheme.outlineVariant),
                _LanguageTile(
                  code: AppStrings.en,
                  label: 'English',
                  selected: language.languageCode == AppStrings.en,
                  onTap: () => language.setLanguage(AppStrings.en),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            tr(AppStrings.settingsLegal),
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _LinkTile(
                  label: tr(AppStrings.settingsPrivacy),
                  url: AppConstants.privacyUrl,
                  onOpen: _open,
                ),
                Divider(height: 1, color: scheme.outlineVariant),
                _LinkTile(
                  label: tr(AppStrings.settingsTerms),
                  url: AppConstants.termsUrl,
                  onOpen: _open,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.label,
    required this.url,
    required this.onOpen,
  });

  final String label;
  final String url;
  final Future<void> Function(String url) onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => onOpen(url),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w400),
              ),
            ),
            Icon(Icons.open_in_new, size: 20, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.code,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String code;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, color: scheme.primary)
            else
              Icon(Icons.circle_outlined, color: scheme.outlineVariant),
          ],
        ),
      ),
    );
  }
}