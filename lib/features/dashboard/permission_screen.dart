import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_transitions.dart';
import 'onboarding_screen.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  bool _notifGranted = false;
  bool _batteryGranted = false;
  bool _alarmGranted = false;
  bool _showAlarm = false;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    _checkInitial();
  }

  Future<void> _checkInitial() async {
    // Bildirim ve pil iznini paralel kontrol et
    final results = await Future.wait([
      Permission.notification.status,
      Permission.ignoreBatteryOptimizations.status,
    ]);

    bool showAlarm = false;
    bool alarm = false;
    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      if (info.version.sdkInt >= 31) {
        showAlarm = true;
        alarm = (await Permission.scheduleExactAlarm.status).isGranted;
      }
    }

    if (mounted) {
      setState(() {
        _notifGranted = results[0].isGranted;
        _batteryGranted = results[1].isGranted;
        _alarmGranted = alarm;
        _showAlarm = showAlarm;
      });
    }
  }

  Future<void> _requestPermission(_PermItem item) async {
    if (_requesting) return;
    setState(() => _requesting = true);

    PermissionStatus? status;
    switch (item.id) {
      case 'notif':
        status = await Permission.notification.request();
        break;
      case 'battery':
        status = await Permission.ignoreBatteryOptimizations.request();
        break;
      case 'alarm':
        status = await Permission.scheduleExactAlarm.request();
        break;
    }

    if (!mounted) return;
    setState(() {
      if (item.id == 'notif') _notifGranted = status?.isGranted ?? false;
      if (item.id == 'battery') _batteryGranted = status?.isGranted ?? false;
      if (item.id == 'alarm') _alarmGranted = status?.isGranted ?? false;
      _requesting = false;
    });
  }

  bool get _canContinue => _notifGranted;

  Future<void> _continue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', true);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      AppTransitions.fadeThrough<void>(const OnboardingScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    final items = [
      _PermItem(
        id: 'notif',
        icon: Icons.notifications_rounded,
        color: colors.primary,
        title: 'Bildirimler',
        description: 'Bir sorun çıktığında anında haberin olur.',
        required: true,
        granted: _notifGranted,
      ),
      _PermItem(
        id: 'battery',
        icon: Icons.battery_charging_full_rounded,
        color: colors.success,
        title: 'Pil Optimizasyonu',
        description: 'Arka planda sessizce çalışmaya devam edebilsin.',
        required: false,
        granted: _batteryGranted,
      ),
      if (_showAlarm)
        _PermItem(
          id: 'alarm',
          icon: Icons.alarm_rounded,
          color: colors.warning,
          title: 'Tam Zamanlı Alarm',
          description: 'Kontroller tam zamanında, gecikmeden çalışsın.',
          required: false,
          granted: _alarmGranted,
        ),
    ];

    return Scaffold(
      backgroundColor: colors.surface0,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Başlık ──────────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [colors.primary, colors.info],
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      boxShadow: [
                        BoxShadow(
                          color: colors.primary.withValues(alpha: 0.3),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.security_rounded,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Son Bir Adım',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Bildirimlerini zamanında alman için birkaç izne '
                        'ihtiyacımız var.',
                        style: TextStyle(color: colors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0),

              const SizedBox(height: 32),

              // ── İzin listesi ─────────────────────────────────────────────
              Expanded(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return _PermCard(
                      item: item,
                      onRequest: () => _requestPermission(item),
                    )
                        .animate()
                        .fadeIn(delay: (i * 100 + 200).ms, duration: 400.ms)
                        .slideX(begin: 0.08, end: 0);
                  },
                ),
              ),

              const SizedBox(height: 16),

              // ── Açıklama ─────────────────────────────────────────────────
              if (!_notifGranted)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border:
                        Border.all(color: colors.error.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: colors.error, size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Devam etmek için bildirim iznine ihtiyacımız var.',
                          style: TextStyle(color: colors.error, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 300.ms),

              const SizedBox(height: 12),

              // ── Devam butonu ─────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: AnimatedOpacity(
                  opacity: _canContinue ? 1.0 : 0.4,
                  duration: AppMotion.base,
                  curve: AppMotion.curve,
                  child: ElevatedButton(
                    onPressed: _canContinue ? _continue : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Devam Et',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded,
                            color: Colors.white, size: 18),
                      ],
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 600.ms, duration: 400.ms),
            ],
          ),
        ),
      ),
    );
  }
}

// ── İzin kartı ────────────────────────────────────────────────────────────────

class _PermItem {
  final String id;
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final bool required;
  final bool granted;

  const _PermItem({
    required this.id,
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.required,
    required this.granted,
  });
}

class _PermCard extends StatelessWidget {
  final _PermItem item;
  final VoidCallback onRequest;

  const _PermCard({required this.item, required this.onRequest});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return AnimatedContainer(
      duration: AppMotion.base,
      curve: AppMotion.curve,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: item.granted
              ? item.color.withValues(alpha: 0.3)
              : colors.hairline,
          width: item.granted ? 1.5 : 1,
        ),
        boxShadow: item.granted
            ? [
                BoxShadow(
                  color: item.color.withValues(alpha: 0.08),
                  blurRadius: 12,
                  spreadRadius: 1,
                )
              ]
            : [],
      ),
      child: Row(
        children: [
          // İkon
          AnimatedContainer(
            duration: AppMotion.base,
            curve: AppMotion.curve,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: item.granted
                  ? item.color.withValues(alpha: 0.15)
                  : colors.surface2,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(
              item.icon,
              color: item.granted ? item.color : colors.textMuted,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),

          // Metin
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (item.required) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.error.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                        child: Text(
                          'Zorunlu',
                          style: TextStyle(
                              color: colors.error,
                              fontSize: 9,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.description,
                  style: TextStyle(
                      color: colors.textSecondary, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Durum / Buton
          item.granted
              ? Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check_rounded, color: item.color, size: 18),
                )
              : GestureDetector(
                  onTap: onRequest,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: item.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                          color: item.color.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'İzin Ver',
                      style: TextStyle(
                        color: item.color,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}
