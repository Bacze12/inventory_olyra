import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:scanflow/core/constants/app_constants.dart';
import 'package:scanflow/data/repositories/settings_repository.dart';
import 'package:scanflow/features/settings/language_provider.dart';
import 'package:scanflow/features/settings/settings_screen.dart';

class _InMemorySettings implements SettingsRepository {
  final Map<String, String> _store = {};

  @override
  Future<String?> get(String key) async => _store[key];

  @override
  Future<String> getOr(String key, String fallback) async {
    final value = _store[key];
    if (value == null || value.trim().isEmpty) return fallback;
    return value;
  }

  @override
  Future<void> set(String key, String value) async {
    _store[key] = value;
  }
}

Widget _buildApp(LanguageProvider provider) => MaterialApp(
      locale: provider.locale,
      supportedLocales: const [Locale('es'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: ChangeNotifierProvider<LanguageProvider>.value(
        value: provider,
        child: const SettingsScreen(),
      ),
    );

void main() {
  late _InMemorySettings repository;

  setUp(() {
    repository = _InMemorySettings();
  });

  testWidgets('muestra el panel de ajustes con Español y English',
      (tester) async {
    final provider = LanguageProvider(repository);
    await provider.init();

    await tester.pumpWidget(_buildApp(provider));

    expect(find.text('Ajustes'), findsOneWidget);
    expect(find.text('Español'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
  });

  testWidgets('al elegir English persiste la selección', (tester) async {
    final provider = LanguageProvider(repository);
    await provider.init();

    await tester.pumpWidget(_buildApp(provider));

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(provider.locale.languageCode, 'en');
    expect(
      await repository.get(AppConstants.settingLanguage),
      'en',
      reason: 'la selección debe quedar persistida para el próximo arranque',
    );
  });

  testWidgets('al volver a Español revierte el idioma persistido',
      (tester) async {
    repository.set(AppConstants.settingLanguage, 'en');
    final provider = LanguageProvider(repository);
    await provider.init();

    await tester.pumpWidget(_buildApp(provider));

    await tester.tap(find.text('Español'));
    await tester.pumpAndSettle();

    expect(provider.locale.languageCode, 'es');
    expect(await repository.get(AppConstants.settingLanguage), 'es');
  });
}