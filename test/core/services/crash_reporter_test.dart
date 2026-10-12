import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mtools/core/services/crash_reporter.dart';
import 'package:mtools/features/dashboard/error_log_service.dart';
import 'package:mtools/core/widgets/error_fallback.dart';

StackTrace _stackAt(String frame) => StackTrace.fromString(
    '#0      _SystemScreenState.build ($frame)\n'
    '#1      SliverReorderableListState._itemBuilder '
    '(package:flutter/src/widgets/reorderable_list.dart:1041:44)');

void main() {
  group('describeError', () {
    test('Sistem ekranındaki hata SYS önekli ve "Sistem" adıyla döner', () {
      final origin = describeError(TypeError(),
          _stackAt('package:mtools/features/dashboard/system_screen.dart:1018:32'));
      expect(origin.screenName, 'Sistem');
      expect(origin.code, matches(RegExp(r'^SYS-[0-9A-F]{4}$')));
    });

    test('aynı hata her seferinde aynı kodu üretir', () {
      final stack =
          _stackAt('package:mtools/features/dashboard/system_screen.dart:1018:32');
      expect(describeError(TypeError(), stack).code,
          describeError(TypeError(), stack).code);
    });

    test('farklı satır farklı kod üretir', () {
      final a = describeError(TypeError(),
          _stackAt('package:mtools/features/dashboard/system_screen.dart:1018:32'));
      final b = describeError(TypeError(),
          _stackAt('package:mtools/features/dashboard/system_screen.dart:1020:32'));
      expect(a.code, isNot(b.code));
    });

    test('dosya tablosunda olmayan özellik dosyası klasöründen eşlenir', () {
      final origin = describeError(StateError('x'),
          _stackAt('package:mtools/features/ups/ups_screen.dart:10:1'));
      expect(origin.screenName, 'UPS');
      expect(origin.code, startsWith('UPS-'));
    });

    test('uygulama karesi yoksa genel APP koduna düşer', () {
      final origin = describeError(StateError('x'), null);
      expect(origin.screenName, 'Uygulama');
      expect(origin.code, startsWith('APP-'));
    });
  });

  test('günlük kaydı hata ekranındakiyle aynı kodu ve stack trace\'i taşır',
      () async {
    SharedPreferences.setMockInitialValues({});
    final error = TypeError();
    final stack =
        _stackAt('package:mtools/features/dashboard/system_screen.dart:1018:32');
    final code = describeError(error, stack).code;

    await logUncaughtError(error, stack);

    final entry = ErrorLogService().logs.first;
    expect(entry.message, contains('[$code]'));
    expect(entry.message, contains('Sistem'));
    expect(entry.detail, contains('system_screen.dart:1018'));
  });

  testWidgets('hata ekranı ekran adını ve kodu gösterir, stack trace göstermez',
      (tester) async {
    final details = FlutterErrorDetails(
      exception: TypeError(),
      stack: _stackAt(
          'package:mtools/features/dashboard/system_screen.dart:1018:32'),
    );
    final expectedCode = describeError(details.exception, details.stack).code;

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: GlobalErrorFallback.fromDetails(details),
    ));

    expect(find.textContaining('Sistem'), findsOneWidget);
    expect(find.textContaining(expectedCode), findsOneWidget);
    expect(find.textContaining('system_screen.dart'), findsNothing);
  });
}
