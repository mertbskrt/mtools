import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtools/core/utils/foreground_polling.dart';

class _CountingProvider extends ChangeNotifier with ForegroundPolling {
  int refreshes = 0;

  @override
  Future<void> refresh() async => refreshes++;
}

void _goBackground(WidgetTester tester) {
  for (final s in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
}

void _goForeground(WidgetTester tester) {
  for (final s in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
}

void main() {
  testWidgets('arka planda durur, ön plana dönünce hemen yenileyip devam eder',
      (tester) async {
    final p = _CountingProvider()..startPolling();

    await tester.pump(const Duration(seconds: 31));
    expect(p.refreshes, 1);

    _goBackground(tester);
    await tester.pump(const Duration(seconds: 120));
    expect(p.refreshes, 1);

    _goForeground(tester);
    await tester.pump();
    expect(p.refreshes, 2);

    await tester.pump(const Duration(seconds: 31));
    expect(p.refreshes, 3);

    p.disposePolling();
  });

  testWidgets('stopPolling sonrası ön plana dönüş döngüyü yeniden başlatmaz',
      (tester) async {
    final p = _CountingProvider()..startPolling();
    _goBackground(tester);
    p.stopPolling();

    _goForeground(tester);
    await tester.pump(const Duration(seconds: 120));
    expect(p.refreshes, 0);

    p.disposePolling();
  });
}
