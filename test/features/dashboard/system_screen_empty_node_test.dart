import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mtools/core/theme/app_theme.dart';
import 'package:mtools/features/dashboard/system_screen.dart';
import 'package:mtools/features/proxmox/proxmox_provider.dart';
import 'package:mtools/shared/models/alias_provider.dart';
import 'package:mtools/widgets/mtools_loader.dart';

/// Gerçek sunucuya hiç bağlanmayan, sadece Sistem ekranının okuduğu alanları
/// dolduran sahte provider. `isConfigured` normalde `_services`'ten türüyor;
/// burada "bir sunucu tanımlı" durumunu taklit etmek için eziliyor.
class _FakeProxmoxProvider extends ProxmoxProvider {
  @override
  bool get isConfigured => true;
}

/// Kullanıcı raporu (3.3.2): tek sunucu, tek node çevrimiçi, 0 CT, 0 VM,
/// AdGuard/UPS tanımlı değil. Node'un status uç noktası boş/eksik dönüyor
/// (banner'da bellek %0, CPU %0).
_FakeProxmoxProvider _singleEmptyNode({Map<String, dynamic>? status}) {
  final id = composeNodeId('192.0.2.10', 'pve');
  final p = _FakeProxmoxProvider()
    ..isReady = true
    ..isInitialLoad = false
    ..nodes = [
      {'node': 'pve', 'status': 'online', '_id': id},
    ]
    ..nodeLXCs = {id: []}
    ..nodeVMs = {id: []};
  if (status != null) p.nodeStatuses = {id: status};
  return p;
}

Future<void> _pumpSystemScreen(
    WidgetTester tester, ProxmoxProvider provider) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ProxmoxProvider>.value(value: provider),
        ChangeNotifierProvider(create: (_) => AliasProvider()),
      ],
      child: AppThemeScope(
        themeData:
            AppThemeData.build(style: AppStyle.classic, isDark: false),
        child: const MaterialApp(home: Scaffold(body: SystemScreen())),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('status hiç gelmemiş tek node — ekran çökmeden açılır',
      (tester) async {
    await _pumpSystemScreen(tester, _singleEmptyNode());

    expect(tester.takeException(), isNull);
    expect(find.text('Sistem Özeti'), findsOneWidget);
    expect(find.text('pve'), findsWidgets);
  });

  testWidgets(
      'status eksik alanlarla gelmiş (cpuinfo/rootfs/loadavg/memory yok) — '
      'ekran çökmeden açılır', (tester) async {
    await _pumpSystemScreen(
        tester, _singleEmptyNode(status: {'cpu': 0, 'uptime': 120}));

    expect(tester.takeException(), isNull);
    expect(find.text('pve'), findsWidgets);
  });

  testWidgets(
      'status/disks/lxc uç noktası hata vermişse sıfır yerine "alınamadı" '
      'gösterilir', (tester) async {
    final provider = _singleEmptyNode();
    final id = provider.nodes.first['_id'] as String;
    provider.nodeFetchFailures = {
      id: {'status', 'disks', 'lxc'},
    };
    await _pumpSystemScreen(tester, provider);

    expect(tester.takeException(), isNull);
    expect(find.text('Kaynak verisi alınamadı'), findsOneWidget);
    expect(find.text('Sistem bilgisi alınamadı'), findsOneWidget);
    expect(find.text('Disk listesi alınamadı'), findsOneWidget);
    expect(
        find.text('Bazı veriler alınamadı: kaynak kullanımı, konteynerler'),
        findsOneWidget);
  });

  testWidgets('ilk yüklemede MToolsLoader "Yükleniyor" etiketiyle görünür',
      (tester) async {
    final provider = _FakeProxmoxProvider()..isReady = false;
    await _pumpSystemScreen(tester, provider);

    expect(find.byType(MToolsLoader), findsOneWidget);
    expect(find.text('Yükleniyor'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('hata yoksa "alınamadı" metni hiç görünmez', (tester) async {
    await _pumpSystemScreen(tester, _singleEmptyNode());

    expect(find.textContaining('alınamadı'), findsNothing);
  });
}
