import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/app_strings.dart';
import 'language_provider.dart';

/// Panel de ajustes con el selector de idioma (español / inglés).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
        ],
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