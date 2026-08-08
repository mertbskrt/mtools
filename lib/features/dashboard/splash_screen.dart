import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/mtools_mark.dart';
import '../../core/utils/app_transitions.dart';
import 'auth_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
    _navigate();
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  Future<void> _navigate() async {
    await Future.wait([
      Future.delayed(const Duration(milliseconds: 1200)),
      FirebaseAuth.instance.authStateChanges().first,
    ]);
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      AppTransitions.fadeThrough<void>(const AuthScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.bgDark,
      body: Stack(
        children: [
          Center(
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    colors.primary.withValues(alpha: 0.06),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const MtoolsMark(size: 72).animate().fadeIn(duration: 600.ms).scale(
                      begin: const Offset(0.8, 0.8),
                      curve: Curves.easeOutBack,
                    ),
                const SizedBox(height: 32),
                Text(
                  'MTools',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 38,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                )
                    .animate()
                    .fadeIn(delay: 300.ms, duration: 500.ms)
                    .slideY(begin: 0.15, end: 0, curve: Curves.easeOut),
                const SizedBox(height: 6),
                Text(
                  'Sunucu Yönetim Sistemi',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.5,
                  ),
                ).animate().fadeIn(delay: 500.ms, duration: 500.ms),
                const SizedBox(height: 56),
                SizedBox(
                  width: 180,
                  child: AnimatedBuilder(
                    animation: _progressController,
                    builder: (context, _) => Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: _progressController.value,
                            backgroundColor:
                                colors.primary.withValues(alpha: 0.08),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              colors.primary.withValues(alpha: 0.7),
                            ),
                            minHeight: 2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _progressController.value < 0.4
                              ? 'Başlatılıyor'
                              : _progressController.value < 0.8
                                  ? 'Yükleniyor'
                                  : 'Hazır',
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 11,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ).animate().fadeIn(delay: 700.ms, duration: 400.ms),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
