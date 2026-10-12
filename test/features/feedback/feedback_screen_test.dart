import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mtools/core/services/crash_reporter.dart';
import 'package:mtools/core/theme/app_theme.dart';
import 'package:mtools/core/widgets/error_fallback.dart';
import 'package:mtools/features/feedback/feedback_screen.dart';
import 'package:mtools/features/feedback/feedback_service.dart';
import 'package:mtools/widgets/mtools_loader.dart';

/// Yanıtı [gate] tamamlanana kadar bekletebilen sahte adapter.
class _Adapter implements HttpClientAdapter {
  final int status;
  final Object? body;
  final bool fail;
  final Completer<void>? gate;
  _Adapter({this.status = 200, this.body, this.fail = false, this.gate});

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? _,
      Future<void>? __) async {
    if (gate != null) await gate!.future;
    if (fail) {
      throw DioException.connectionError(requestOptions: o, reason: 'offline');
    }
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// Cihaz/paket eklentileri testte yok — gönderimde sabit alanlar kullanılsın.
class _TestService extends FeedbackService {
  _TestService(_Adapter adapter)
      : super(dio: Dio()..httpClientAdapter = adapter, appKey: 'k');

  @override
  Future<FeedbackResult> send({
    required FeedbackType type,
    required String name,
    required String email,
    required String message,
    required bool includeLog,
    Map<String, String>? deviceFields,
  }) =>
      super.send(
        type: type,
        name: name,
        email: email,
        message: message,
        includeLog: includeLog,
        deviceFields: const {'surum': '3.4.0 (24)', 'cihaz': 'X', 'android': '14'},
      );
}

Widget _host(Widget child) => AppThemeScope(
      themeData: AppThemeData.build(style: AppStyle.classic, isDark: false),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => child)),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _open(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(_host(screen));
  await tester.tap(find.text('aç'));
  await tester.pumpAndSettle();
}

Future<void> _fillValid(WidgetTester tester) async {
  await tester.enterText(
      find.widgetWithText(TextFormField, 'E-posta'), 'ali@example.com');
  await tester.enterText(
      find.widgetWithText(TextFormField, 'Mesaj'), 'Bu bir deneme mesajıdır.');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('anahtar yoksa form yerine e-posta seçeneği görünür',
      (tester) async {
    await _open(tester, FeedbackScreen(service: FeedbackService(appKey: '')));

    expect(find.text('Gönder'), findsNothing);
    expect(find.textContaining('contact@mtools.tr adresine yazın'),
        findsOneWidget);
    expect(find.text('E-posta gönder'), findsOneWidget);
  });

  testWidgets('e-posta ve en az 10 karakterlik mesaj zorunlu', (tester) async {
    await _open(tester, FeedbackScreen(service: _TestService(_Adapter())));

    await tester.enterText(find.widgetWithText(TextFormField, 'Mesaj'), 'kısa');
    await tester.tap(find.text('Gönder'));
    await tester.pump();

    expect(find.text('E-posta adresi gerekli'), findsOneWidget);
    expect(find.text('Mesaj en az 10 karakter olmalı'), findsOneWidget);
  });

  testWidgets('mesaj alanı 3000 karakter sayacı gösterir', (tester) async {
    await _open(tester, FeedbackScreen(service: _TestService(_Adapter())));
    expect(find.text('0/3000'), findsOneWidget);
  });

  testWidgets('hata ekranından açılınca tür, günlük ve mesaj ön doldurulur',
      (tester) async {
    await _open(
        tester,
        FeedbackScreen.forError(const ErrorOrigin('Sistem', 'SYS-7F3A'),
            service: _TestService(_Adapter())));

    final chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Hata bildirimi'));
    expect(chip.selected, isTrue);
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue);
    expect(find.textContaining('Ekran: Sistem · Kod: SYS-7F3A'), findsOneWidget);
  });

  testWidgets('gönderirken buton pasif ve içinde MToolsLoader var; ok:true '
      'onay mesajı gösterip kapanır', (tester) async {
    final gate = Completer<void>();
    await _open(
        tester,
        FeedbackScreen(
            service: _TestService(_Adapter(body: {'ok': true}, gate: gate))));
    await _fillValid(tester);

    await tester.tap(find.text('Gönder'));
    await tester.pump();
    final button =
        tester.widget<ElevatedButton>(find.byType(ElevatedButton).last);
    expect(button.onPressed, isNull);
    expect(find.descendant(
            of: find.byType(ElevatedButton).last,
            matching: find.byType(MToolsLoader)),
        findsOneWidget);

    gate.complete();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));

    expect(
        find.text('Mesajınız alındı. E-posta adresinize bir onay gönderdik.'),
        findsOneWidget);
    expect(find.byType(FeedbackScreen), findsNothing);
  });

  for (final (name, adapter, expected) in [
    (
      'ok:false sunucunun hata metnini gösterir',
      _Adapter(status: 400, body: {'ok': false, 'hata': 'Geçersiz e-posta'}),
      'Geçersiz e-posta'
    ),
    (
      '429 hız sınırı mesajını gösterir',
      _Adapter(status: 429, body: {'ok': false}),
      'Çok fazla deneme yapıldı, lütfen biraz sonra tekrar deneyin.'
    ),
    (
      'ağ hatası bağlantı mesajını gösterir',
      _Adapter(fail: true),
      'Gönderilemedi. İnternet bağlantınızı kontrol edin ya da '
          'contact@mtools.tr adresine yazın.'
    ),
  ]) {
    testWidgets(name, (tester) async {
      await _open(tester, FeedbackScreen(service: _TestService(adapter)));
      await _fillValid(tester);
      await tester.tap(find.text('Gönder'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(expected), findsOneWidget);
      expect(find.byType(FeedbackScreen), findsOneWidget);
      // Hata kutusu eklenince buton test ekranının altına kayabiliyor.
      await tester.scrollUntilVisible(find.text('Gönder'), 100,
          scrollable: find.byType(Scrollable).first);
      expect(
          tester.widget<ElevatedButton>(find.byType(ElevatedButton).last)
              .onPressed,
          isNotNull);
    });
  }

  testWidgets('hata ekranındaki "Bu hatayı bildir" kendi kodunu iletir',
      (tester) async {
    ErrorOrigin? reported;
    const origin = ErrorOrigin('Sistem', 'SYS-7F3A');
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: GlobalErrorFallback(origin: origin, onReport: (o) => reported = o),
    ));

    await tester.tap(find.text('Bu hatayı bildir'));
    expect(reported?.code, 'SYS-7F3A');
  });

  testWidgets('onReport verilmezse hata ekranında buton görünmez',
      (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: GlobalErrorFallback(origin: ErrorOrigin('Sistem', 'SYS-7F3A')),
    ));
    expect(find.text('Bu hatayı bildir'), findsNothing);
  });
}
