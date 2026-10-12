import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mtools/core/constants/links.dart';
import 'package:mtools/core/theme/app_theme.dart';
import 'package:mtools/features/dashboard/about_screen.dart';
import 'package:mtools/features/dashboard/error_log_screen.dart';
import 'package:mtools/features/feedback/feedback_screen.dart';
import 'package:mtools/features/update/update_screen.dart';

void main() {
  late List<Uri> opened;
  late bool launchResult;
  late bool launchThrows;

  Future<bool> fakeLauncher(Uri uri, {LaunchMode mode = LaunchMode.platformDefault}) async {
    expect(mode, LaunchMode.externalApplication);
    opened.add(uri);
    if (launchThrows) throw Exception('tarayıcı yok');
    return launchResult;
  }

  setUp(() {
    opened = [];
    launchResult = true;
    launchThrows = false;
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'MTools',
      packageName: 'com.example.mtools_v2',
      version: '3.4.0',
      buildNumber: '24',
      buildSignature: '',
    );
  });

  Future<void> pumpAbout(WidgetTester tester, {bool dark = false}) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppThemeScope(
      themeData: AppThemeData.build(style: AppStyle.classic, isDark: dark),
      child: MaterialApp(home: AboutScreen(urlLauncher: fakeLauncher)),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tapRow(WidgetTester tester, String title) async {
    await tester.ensureVisible(find.text(title));
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  testWidgets('sürüm v3.4.0 (24) görünür; 5 dokunuş Hata Günlüğü\'nü açar',
      (tester) async {
    await pumpAbout(tester);
    final version = find.text('v3.4.0 (24)');
    expect(version, findsOneWidget);

    for (var i = 0; i < 4; i++) {
      await tester.tap(version);
      await tester.pump();
    }
    expect(find.byType(ErrorLogScreen), findsNothing);

    await tester.tap(version);
    await tester.pumpAndSettle();
    expect(find.byType(ErrorLogScreen), findsOneWidget);
  });

  testWidgets('dış bağlantılar doğru adrese, dış tarayıcıda açılır',
      (tester) async {
    await pumpAbout(tester);

    await tapRow(tester, 'Web sitesi');
    await tapRow(tester, 'Gizlilik politikası');
    await tapRow(tester, 'İletişim');

    expect(opened[0].toString(), 'https://mtools.tr');
    expect(opened[1].toString(), 'https://mtools.tr/gizlilik/');
    expect(opened[2].scheme, 'mailto');
    expect(opened[2].path, MToolsLinks.contactEmail);
  });

  testWidgets('açılamayan ya da hata veren bağlantı "Bağlantı açılamadı" '
      'gösterir, çökmez', (tester) async {
    await pumpAbout(tester);

    launchResult = false;
    await tapRow(tester, 'Web sitesi');
    expect(find.text('Bağlantı açılamadı'), findsOneWidget);

    ScaffoldMessenger.of(tester.element(find.byType(AboutScreen)))
        .removeCurrentSnackBar();
    await tester.pumpAndSettle();

    launchThrows = true;
    await tapRow(tester, 'Gizlilik politikası');
    expect(tester.takeException(), isNull);
    expect(find.text('Bağlantı açılamadı'), findsOneWidget);
  });

  testWidgets('dış bağlantı satırlarında open_in_new ikonu var', (tester) async {
    await pumpAbout(tester);
    for (final title in ['Web sitesi', 'İletişim', 'Gizlilik politikası']) {
      final tile = find.ancestor(
          of: find.text(title), matching: find.byType(ListTile));
      expect(
          find.descendant(of: tile, matching: find.byIcon(Icons.open_in_new)),
          findsOneWidget,
          reason: title);
    }
  });

  testWidgets('Güncellemeleri denetle ve Geri bildirim mevcut ekranları açar',
      (tester) async {
    await pumpAbout(tester);
    await tester.tap(find.text('Güncellemeleri denetle'));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateScreen), findsOneWidget);

    Navigator.of(tester.element(find.byType(UpdateScreen))).pop();
    await tester.pumpAndSettle();
    await tapRow(tester, 'Geri bildirim gönder');
    expect(find.byType(FeedbackScreen), findsOneWidget);
  });

  testWidgets('Sürüm notları bu sürümün notlarını ve Tüm sürümler bağlantısını '
      'gösterir', (tester) async {
    await pumpAbout(tester);
    await tapRow(tester, 'Sürüm notları');

    expect(find.text('Sürüm Notları'), findsOneWidget);
    expect(find.text('v3.4.0'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Tüm sürümler'), 300);
    expect(find.text('Tüm sürümler'), findsOneWidget);
  });

  testWidgets('lisans sayfası MTools adı, sürümü ve © 2026 MTools ile açılır',
      (tester) async {
    await pumpAbout(tester);
    await tapRow(tester, 'Açık kaynak lisansları');

    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('MTools'), findsWidgets);
    expect(find.text('v3.4.0 (24)'), findsWidgets);
    expect(find.text('© 2026 MTools'), findsOneWidget);
  });

  testWidgets('ekranda kişisel isim ya da kullanıcı adı yok; alt bilgi doğru',
      (tester) async {
    for (final dark in [false, true]) {
      await pumpAbout(tester, dark: dark);
      expect(find.textContaining(RegExp('mert|başkurt|baskurt|bskrt',
          caseSensitive: false)), findsNothing);
      expect(find.text('mtools.tr · contact@mtools.tr'), findsOneWidget);
      for (final group in ['UYGULAMA', 'DESTEK', 'YASAL']) {
        expect(find.text(group), findsOneWidget);
      }
    }
  });
}
