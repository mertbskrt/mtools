import 'package:flutter/widgets.dart';

/// Yalnızca `--dart-define=MTOOLS_TEST_ERRORS=true` ile derlenen test
/// sürümlerinde açık. Derleme zamanı sabiti olduğu için normal derlemede
/// `if (kTestErrorsEnabled)` dalları ve bu ekran derleyici tarafından
/// tamamen atılır — arayüzde hiçbir izi kalmaz.
const kTestErrorsEnabled = bool.fromEnvironment('MTOOLS_TEST_ERRORS');

/// build() sırasında bilerek hata fırlatır: release modunda hata ekranının
/// (GlobalErrorFallback — ekran adı, kod, "Bu hatayı bildir") ve hata
/// günlüğü kaydının cihazda denenebilmesi için.
class TestErrorScreen extends StatelessWidget {
  const TestErrorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    throw StateError('MTOOLS_TEST_ERRORS ile tetiklenen test hatası');
  }
}
