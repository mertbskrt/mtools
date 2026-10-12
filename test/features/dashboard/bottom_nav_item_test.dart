import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtools/core/theme/app_theme.dart';
import 'package:mtools/features/dashboard/bottom_nav_item.dart';

void main() {
  late List<String> haptics;
  late List<int> taps;

  setUp(() {
    haptics = [];
    taps = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics.add(call.arguments as String);
      }
      return null;
    });
  });

  /// home_screen.dart'taki alt menüyle aynı düzen: 64 px yüksek Row,
  /// her hücre Expanded.
  Future<void> pumpBar(WidgetTester tester,
      {int current = 0, bool tourActive = false}) {
    return tester.pumpWidget(AppThemeScope(
      themeData: AppThemeData.build(style: AppStyle.classic, isDark: false),
      child: MaterialApp(
        home: Scaffold(
          bottomNavigationBar: SizedBox(
            height: 64,
            child: Row(
              children: [
                for (var i = 0; i < 3; i++)
                  Expanded(
                    child: BottomNavItem(
                      key: ValueKey('tab$i'),
                      icon: Icons.dashboard_rounded,
                      label: 'Sekme $i',
                      index: i,
                      currentIndex: current,
                      tourActive: tourActive,
                      onTap: taps.add,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets('başka sekmeye dokununca bir kez selectionClick ve geçiş',
      (tester) async {
    await pumpBar(tester);
    await tester.tap(find.text('Sekme 1'));

    expect(taps, [1]);
    expect(haptics, ['HapticFeedbackType.selectionClick']);
  });

  testWidgets('seçili sekmeye tekrar dokununca titreşim ve geçiş yok',
      (tester) async {
    await pumpBar(tester, current: 1);
    await tester.tap(find.text('Sekme 1'));

    expect(taps, isEmpty);
    expect(haptics, isEmpty);
  });

  testWidgets('tanıtım turu sırasında dokunma hiçbir şey yapmaz',
      (tester) async {
    await pumpBar(tester, tourActive: true);
    await tester.tap(find.text('Sekme 2'));

    expect(taps, isEmpty);
    expect(haptics, isEmpty);
  });

  testWidgets('hücrenin ikondan uzak köşesine dokunmak da sekmeyi seçer',
      (tester) async {
    await pumpBar(tester);
    final cell = tester.getRect(find.byKey(const ValueKey('tab2')));
    // Sağ üst köşeye yakın — ikon ve etiket hücrenin ortasında.
    await tester.tapAt(cell.topRight + const Offset(-3, 3));

    expect(taps, [2]);
    expect(haptics, hasLength(1));
  });
}
