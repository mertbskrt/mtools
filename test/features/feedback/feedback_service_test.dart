import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mtools/features/dashboard/error_log_service.dart';
import 'package:mtools/features/feedback/feedback_service.dart';
import 'package:mtools/core/constants/links.dart';

/// İsteği kaydeden ve önceden belirlenmiş yanıtı (ya da hatayı) dönen adapter.
class _FakeAdapter implements HttpClientAdapter {
  final int status;
  final Object? body;
  final bool fail;
  RequestOptions? lastRequest;
  Map<String, dynamic>? lastBody;

  _FakeAdapter({this.status = 200, this.body, this.fail = false});

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    lastRequest = options;
    lastBody = Map<String, dynamic>.from(options.data as Map);
    if (fail) {
      throw DioException.connectionError(
          requestOptions: options, reason: 'offline');
    }
    return ResponseBody.fromString(jsonEncode(body), status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        });
  }

  @override
  void close({bool force = false}) {}
}

const _device = {'surum': '3.4.0 (24)', 'cihaz': 'Samsung SM-S918B', 'android': '14'};

Future<(FeedbackResult, _FakeAdapter)> _send(_FakeAdapter adapter,
    {bool includeLog = false}) async {
  final dio = Dio()..httpClientAdapter = adapter;
  final result = await FeedbackService(dio: dio, appKey: 'test-key').send(
    type: FeedbackType.oneri,
    name: '  Ali ',
    email: 'ali@example.com',
    message: 'Bu bir deneme mesajıdır.',
    includeLog: includeLog,
    deviceFields: _device,
  );
  return (result, adapter);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('istek uç noktaya, anahtar başlığıyla ve beklenen gövdeyle gider',
      () async {
    final (result, a) = await _send(_FakeAdapter(body: {'ok': true}));

    expect(result, isA<FeedbackSent>());
    expect(a.lastRequest!.uri.toString(), MToolsLinks.feedbackEndpoint);
    expect(a.lastRequest!.method, 'POST');
    expect(a.lastRequest!.headers['X-MTools-App'], 'test-key');
    expect(a.lastRequest!.contentType, startsWith('application/json'));
    expect(a.lastBody, {
      'tur': 'oneri',
      'ad': 'Ali',
      'eposta': 'ali@example.com',
      'mesaj': 'Bu bir deneme mesajıdır.',
      ..._device,
      'dil': FeedbackService.deviceLanguage(),
      'gunluk': '',
    });
  });

  test('{ok:false, hata} sunucunun metnini döner', () async {
    final (result, _) = await _send(
        _FakeAdapter(status: 400, body: {'ok': false, 'hata': 'Geçersiz e-posta'}));
    expect((result as FeedbackRejected).message, 'Geçersiz e-posta');
  });

  test('429 hız sınırı olarak ayrışır', () async {
    final (result, _) =
        await _send(_FakeAdapter(status: 429, body: {'ok': false, 'hata': 'x'}));
    expect(result, isA<FeedbackRateLimited>());
  });

  test('bağlantı hatası ağ hatası olarak döner', () async {
    final (result, _) = await _send(_FakeAdapter(fail: true));
    expect(result, isA<FeedbackNetworkError>());
  });

  test('anlaşılamayan yanıt kullanıcıya açıklamalı hata döner', () async {
    final (result, _) = await _send(_FakeAdapter(status: 502, body: 'gateway'));
    expect((result as FeedbackRejected).message, contains('502'));
  });

  test('günlük işaretliyse son kayıtlar gövdeye eklenir', () async {
    await ErrorLogService().clear();
    await ErrorLogService()
        .log(type: ErrorLogType.refresh, message: 'Node verisi alınamadı: pve / disks');
    final (_, a) = await _send(_FakeAdapter(body: {'ok': true}), includeLog: true);
    expect(a.lastBody!['gunluk'], contains('Node verisi alınamadı: pve / disks'));
  });

  test('günlük en fazla 50 kayıt ve 15.000 karakterle sınırlı', () {
    final logs = List.generate(
      80,
      (i) => ErrorLogEntry(
        id: '$i',
        time: DateTime(2026, 10, 12),
        type: ErrorLogType.unknown,
        message: 'kayıt $i',
        detail: 'x' * 500,
      ),
    );
    final text = FeedbackService.formatLog(logs);
    expect(text.length, lessThanOrEqualTo(FeedbackService.maxLogChars));
    expect(text, contains('kayıt 0'));
    expect(text, isNot(contains('kayıt 50')));

    final short = FeedbackService.formatLog(logs.take(60).map((e) =>
        ErrorLogEntry(id: e.id, time: e.time, type: e.type, message: e.message))
        .toList());
    expect('kayıt'.allMatches(short).length, 50);
  });

  test('dil: Türkçe cihaz "tr", diğerleri "en"', () {
    expect(FeedbackService.deviceLanguage(const Locale('tr', 'TR')), 'tr');
    expect(FeedbackService.deviceLanguage(const Locale('de')), 'en');
  });

  test('anahtar boşsa servis yapılandırılmamış sayılır', () {
    expect(FeedbackService(appKey: '').isConfigured, isFalse);
    expect(FeedbackService(appKey: 'k').isConfigured, isTrue);
  });
}
