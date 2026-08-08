import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:showcaseview/showcaseview.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/mtools_mark.dart';
import '../../core/utils/app_transitions.dart'; // ← YENİ
import '../notifications/notification_history_screen.dart';
import '../dashboard/settings_screen.dart';
import '../dashboard/system_screen.dart';
import '../proxmox/proxmox_screen.dart';
import '../../shared/models/tab_config.dart';
import '../wol/wol_screen.dart';
import '../terminal/terminal_screen.dart';
import '../adguard/adguard_screen.dart';
import '../ups/ups_screen.dart';
import '../proxmox/proxmox_provider.dart';
import '../../core/services/connectivity_provider.dart';
import '../../shared/widgets/connection_error_view.dart';
import '../update/update_service.dart';
import '../update/update_dialog.dart';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  final bool startTour;
  const HomeScreen({super.key, this.startTour = false});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  bool _tourActive = false;

  late final Map<String, Widget> _pageCache;
  late final Widget _wolScreen;

  final _showcaseAppBar = GlobalKey();
  final _showcaseSistem = GlobalKey();
  final _showcaseProxmox = GlobalKey();
  final _showcaseAdguard = GlobalKey();
  final _showcaseUps = GlobalKey();
  final _showcaseTerminal = GlobalKey();
  final _showcaseWol = GlobalKey();
  final _showcaseAyarlar = GlobalKey();

  Widget _getPage(String id) {
    if (id == 'wol') return _wolScreen;
    return _pageCache[id] ?? const SizedBox.shrink();
  }

  static IconData _getIcon(String id) {
    switch (id) {
      case 'sistem':
        return Icons.dashboard_rounded;
      case 'proxmox':
        return Icons.storage_rounded;
      case 'adguard':
        return Icons.shield_rounded;
      case 'ups':
        return Icons.battery_charging_full_rounded;
      case 'terminal':
        return Icons.terminal_rounded;
      case 'wol':
        return Icons.power_settings_new_rounded;
      default:
        return Icons.widgets;
    }
  }

  GlobalKey? _showcaseKeyFor(String id) {
    switch (id) {
      case 'sistem':
        return _showcaseSistem;
      case 'proxmox':
        return _showcaseProxmox;
      case 'adguard':
        return _showcaseAdguard;
      case 'ups':
        return _showcaseUps;
      case 'terminal':
        return _showcaseTerminal;
      case 'wol':
        return _showcaseWol;
      default:
        return null;
    }
  }

  String _tourDescription(String id) {
    switch (id) {
      case 'sistem':
        return 'Sistem — sunucularının nabzını buradan tut.';
      case 'proxmox':
        return 'Proxmox — bir satıra basılı tutarak başlat, durdur ya da yeniden başlat.';
      case 'adguard':
        return 'AdGuard — reklam ve takip engellemeni buradan izle.';
      case 'ups':
        return 'UPS — güç kesilirse önceden haberin olur.';
      case 'terminal':
        return 'Terminal — sunucuna doğrudan, komut satırından bağlan.';
      case 'wol':
        return 'Wake on LAN — kapalı bir cihazı uzaktan uyandır.';
      default:
        return '';
    }
  }

  List<TabItem> _navTabs(List<TabItem> tabs) =>
      tabs.where((t) => t.id != 'ayarlar').toList();

  @override
  void initState() {
    super.initState();
    _pageCache = {
      'sistem': const SystemScreen(),
      'proxmox': const ProxmoxScreen(),
      'adguard': const AdGuardScreen(),
      'ups': const UpsScreen(),
      'terminal': const TerminalScreen(),
    };
    _wolScreen = const WolScreen();
    if (widget.startTour) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 500), _startTour);
      });
    }
    _checkForUpdate();
  }

  /// Uygulama açılışında bir kez çalışır. Açılışı bloklamaz, ağ hatasını
  /// (veya imza doğrulaması başarısız olursa) sessizce yutar — uygulama
  /// normal şekilde açılmaya devam eder. Yalnızca gerçekten yeni ve
  /// imzası doğrulanmış bir sürüm varsa diyalog gösterilir.
  Future<void> _checkForUpdate() async {
    try {
      final result = await UpdateService().check();
      if (!mounted || !result.updateAvailable || result.manifest == null) {
        return;
      }
      await showUpdateDialog(
        context,
        manifest: result.manifest!,
        mandatory: result.mandatory,
      );
    } catch (e) {
      // Bilinçli sessiz: arka planda otomatik güncelleme kontrolü — ağ yoksa
      // ya da sunucu yanıt vermezse kullanıcıya bir hata göstermeye gerek
      // yok, Ayarlar'daki elle kontrol her zaman kullanılabilir.
      debugPrint('Güncelleme kontrolü atlandı: $e');
    }
  }

  void _startTour() {
    if (!mounted) return;
    setState(() => _tourActive = true);
    final tabs = _navTabs(context.read<TabConfigProvider>().visibleTabs);
    final keys = <GlobalKey>[_showcaseAppBar];
    for (final tab in tabs) {
      final key = _showcaseKeyFor(tab.id);
      if (key != null) keys.add(key);
    }
    keys.add(_showcaseAyarlar);
    ShowCaseWidget.of(context).startShowCase(keys);
  }

  // ── Ayarlar sayfasına geçiş — artık slide+fade animasyonlu ──────────────
  Future<void> _openSettings({bool startTour = false}) async {
    await Navigator.push(
      context,
      AppTransitions.slideFade(SettingsScreen(startTour: startTour)),
    );
    if (mounted) setState(() => _tourActive = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    final allTabs = context.select<TabConfigProvider, List<TabItem>>(
      (p) => p.visibleTabs,
    );

    if (allTabs.isEmpty) {
      return Scaffold(
        backgroundColor: colors.surface0,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final tabs = _navTabs(allTabs);
    if (_currentIndex >= tabs.length) {
      // build dışında düzelt — bir sonraki frame'de güvenli
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _currentIndex = 0);
      });
      return Scaffold(
        backgroundColor: colors.surface0,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final hasInternet =
        context.select<ConnectivityProvider, bool>((p) => p.hasInternet);
    final isOffline = context.select<ProxmoxProvider, bool>((p) => p.isOffline);
    final retryStatus =
        context.select<ProxmoxProvider, String?>((p) => p.retryStatus);
    final isOperationInProgress =
        context.select<ProxmoxProvider, bool>((p) => p.isOperationInProgress);
    final currentTabId = tabs.isNotEmpty ? tabs[_currentIndex].id : '';

    return Scaffold(
      backgroundColor: colors.surface0,
      appBar: isOperationInProgress
          ? null
          : AppBar(
              backgroundColor: colors.surface0,
              elevation: 0,
              scrolledUnderElevation: 0,
              titleSpacing: 0,
              // Logo AppBar'ın title/actions slotlarından tamamen çıkarılıp
              // flexibleSpace'e taşındı — bu, sağdaki actions grubunun
              // genişliğinden bağımsız GERÇEK ekran-genişliği merkezini
              // garanti eder ("kalan boşluğun ortası" değil).
              // flexibleSpace status bar + toolbar'ın TOPLAMINI kaplıyor, ama
              // actions/title sadece status bar ALTINDAKİ toolbar satırında —
              // SafeArea(bottom:false) olmadan Center bu ikisini aynı dikey
              // eksene oturtamıyordu (logo actions ikonlarından yukarıda
              // duruyordu). Yatay tam-ekran merkezleme (asıl amaç) bozulmaz.
              flexibleSpace: SafeArea(
                bottom: false,
                child: Center(
                  child: Showcase(
                    key: _showcaseAppBar,
                    description: 'Burası MTools. Devam etmek için dokun.',
                    tooltipBackgroundColor: colors.surface1,
                    textColor: colors.textPrimary,
                    descTextStyle:
                        TextStyle(color: colors.textSecondary, fontSize: 13),
                    scaleAnimationDuration: AppMotion.base,
                    scaleAnimationCurve: AppMotion.curve,
                    onBarrierClick: () => ShowCaseWidget.of(context).next(),
                    onToolTipClick: () => ShowCaseWidget.of(context).next(),
                    // Optik ince ayar: işaretin görsel ağırlığı (nokta) sağda —
                    // tam geometrik merkez gözle hafif sağa kaymış hissettiriyor.
                    // NOT: logo flexibleSpace üzerinden TÜM ekran genişliğinde
                    // ortalanıyor — leading/actions'daki içerik miktarından
                    // bağımsız, bu yüzden zili leading'e taşımak merkezlemeyi
                    // etkilemez.
                    child: Transform.translate(
                      offset: const Offset(-1, 0),
                      child: const MtoolsMark(size: 32),
                    ),
                  ),
                ),
              ),
              leading: Container(
                margin: const EdgeInsets.only(left: 8),
                child: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: colors.surface2,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: colors.hairline),
                    ),
                    child: Icon(
                      Icons.notifications_none_rounded,
                      color: colors.textSecondary,
                      size: 18,
                    ),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    AppTransitions.slideFade(const NotificationHistoryScreen()),
                  ),
                ),
              ),
              actions: [
                if (currentTabId == 'sistem' || currentTabId == 'proxmox')
                  const _AppBarRefreshButton(),
                Showcase(
                  key: _showcaseAyarlar,
                  description: 'Ayarlar — tema, sunucuların ve bildirimlerin burada.',
                  tooltipBackgroundColor: colors.surface1,
                  textColor: colors.textPrimary,
                  descTextStyle:
                      TextStyle(color: colors.textSecondary, fontSize: 13),
                  scaleAnimationDuration: AppMotion.base,
                  scaleAnimationCurve: AppMotion.curve,
                  disposeOnTap: true,
                  onTargetClick: () {
                    ShowCaseWidget.of(context).dismiss();
                    _openSettings(startTour: true);
                  },
                  onBarrierClick: () {
                    ShowCaseWidget.of(context).dismiss();
                    _openSettings(startTour: true);
                  },
                  onToolTipClick: () {
                    ShowCaseWidget.of(context).dismiss();
                    _openSettings(startTour: true);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    child: IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: colors.surface2,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(color: colors.hairline),
                        ),
                        child: Icon(
                          Icons.settings_rounded,
                          color: colors.textSecondary,
                          size: 18,
                        ),
                      ),
                      onPressed: () => _openSettings(startTour: _tourActive),
                    ),
                  ),
                ),
              ],
            ),
      body: Column(
        children: [
          // Proxmox'a özel yeniden bağlanma bildirimi sadece cihazın gerçek
          // interneti varken ama sunucuya özel olarak ulaşılamıyorken
          // gösterilir — internet tamamen yoksa aşağıdaki genel "Bağlantı
          // Yok" ekranı zaten tüm sekmelerin yerini alıyor, ikisi birden
          // gösterilip kafa karıştırmasın diye.
          if (isOffline && hasInternet)
            _OfflineBanner(
              status: retryStatus,
              onRetry: () => context.read<ProxmoxProvider>().manualRefresh(),
            ),
          Expanded(
            // Sekmeler arası geçiş anlık (animasyonsuz) — iOS tab bar
            // davranışı. IndexedStack tüm sekmeleri ağaçta tutar (scroll
            // konumu/genişletme durumu korunur, rebuild maliyeti yok);
            // internet yokken üzerine tam ekran "Bağlantı Yok" katmanı
            // biner — sekmeye tekrar girip çıkmaya gerek kalmaz, bağlantı
            // geri geldiği an katman kayboluyor.
            child: Stack(
              children: [
                IndexedStack(
                  index: _currentIndex,
                  // `_getPage` cache'den alıyor, list sadece tabs değişince yeniden yaratılır
                  children: List<Widget>.unmodifiable(
                      tabs.map((tab) => _getPage(tab.id))),
                ),
                if (!hasInternet)
                  Positioned.fill(
                    child: Container(
                      color: colors.surface0,
                      child: ConnectionErrorView(
                        onRetry: () => context
                            .read<ConnectivityProvider>()
                            .recheckNow(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isOperationInProgress
          ? null
          : Container(
              decoration: BoxDecoration(
                color: colors.surface1,
                border: Border(top: BorderSide(color: colors.hairline)),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: 64,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: tabs.asMap().entries.map((entry) {
                      final tab = entry.value;
                      final showcaseKey = _showcaseKeyFor(tab.id);
                      final navItem = _NavItem(
                        key: ValueKey(tab.id),
                        icon: _getIcon(tab.id),
                        label: tab.label,
                        index: entry.key,
                        currentIndex: _currentIndex,
                        tourActive: _tourActive,
                        onTap: (idx) {
                          if (!_tourActive) setState(() => _currentIndex = idx);
                        },
                      );

                      if (showcaseKey != null) {
                        return Showcase(
                          key: showcaseKey,
                          description: _tourDescription(tab.id),
                          tooltipBackgroundColor: colors.surface1,
                          textColor: colors.textPrimary,
                          descTextStyle: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 13,
                          ),
                          scaleAnimationDuration: AppMotion.base,
                          scaleAnimationCurve: AppMotion.curve,
                          onBarrierClick: () =>
                              ShowCaseWidget.of(context).next(),
                          onToolTipClick: () =>
                              ShowCaseWidget.of(context).next(),
                          child: navItem,
                        );
                      }
                      return navItem;
                    }).toList(),
                  ),
                ),
              ),
            ),
    );
  }
}

// ── Offline Banner ────────────────────────────────────────────────────────────

class _OfflineBanner extends StatelessWidget {
  final String? status;
  final VoidCallback onRetry;

  const _OfflineBanner({this.status, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.errorMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off_rounded, color: colors.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              status ?? 'Bağlantı kurulamadı',
              style: TextStyle(color: colors.error, fontSize: 12),
            ),
          ),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: colors.error.withValues(alpha: 0.4)),
              ),
              child: Text(
                'Yenile',
                style: TextStyle(
                  color: colors.error,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Nav Item ──────────────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int currentIndex;
  final bool tourActive;
  final void Function(int) onTap;

  const _NavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.index,
    required this.currentIndex,
    required this.tourActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final bool isSelected = index == currentIndex;

    return GestureDetector(
      onTap: () => onTap(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: AppMotion.base,
              curve: AppMotion.curve,
              transform: Matrix4.translationValues(0, isSelected ? -2 : 0, 0),
              child: Icon(
                icon,
                color: isSelected ? colors.primary : colors.textMuted,
                size: isSelected ? 24 : 20,
              ),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: AppMotion.base,
              curve: AppMotion.curve,
              style: TextStyle(
                color: isSelected ? colors.primary : colors.textMuted,
                fontSize: isSelected ? 9.5 : 8.5,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}

// ── AppBar Refresh Button ─────────────────────────────────────────────────────

class _AppBarRefreshButton extends StatefulWidget {
  const _AppBarRefreshButton();

  @override
  State<_AppBarRefreshButton> createState() => _AppBarRefreshButtonState();
}

class _AppBarRefreshButtonState extends State<_AppBarRefreshButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _showSuccess = false;
  Timer? _successTimer; // dart:async import gerekli

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  @override
  void dispose() {
    _successTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLoading = context.select<ProxmoxProvider, bool>((p) => p.isLoading);

    return AnimatedSwitcher(
      duration: AppMotion.base,
      switchInCurve: AppMotion.curve,
      switchOutCurve: AppMotion.curve,
      child: _showSuccess
          ? IconButton(
              key: const ValueKey('success'),
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: colors.success.withValues(alpha: 0.3)),
                ),
                child: Icon(Icons.check_rounded, color: colors.success, size: 18),
              ),
              onPressed: null,
            )
          : RotationTransition(
              key: const ValueKey('refresh'),
              turns: _controller,
              child: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: colors.surface2,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: colors.hairline),
                  ),
                  child: Icon(
                    Icons.refresh_rounded,
                    color: isLoading ? colors.textMuted : colors.textSecondary,
                    size: 18,
                  ),
                ),
                onPressed: isLoading
                    ? null
                    : () async {
                        _controller.repeat();
                        await context.read<ProxmoxProvider>().manualRefresh();
                        _controller.stop();
                        _controller.reset();
                        if (mounted) {
                          setState(() => _showSuccess = true);
                          _successTimer = Timer(const Duration(milliseconds: 1500), () {
                            if (mounted) setState(() => _showSuccess = false);
                          });
                        }
                      },
              ),
            ),
    );
  }
}
