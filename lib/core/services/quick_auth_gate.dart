import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../utils/app_transitions.dart';

class QuickAuthGate {
  QuickAuthGate._();

  static Future<bool> isScopeGated(
      {required String scopeKey}) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('quick_auth_kill_switch') ?? false) return false;
    if (!(prefs.getBool(scopeKey) ?? false)) return false;
    final lockType = prefs.getString('lock_type') ?? 'none';
    return lockType != 'none';
  }

  static Future<bool> verify(BuildContext context,
      {required String localizedReason}) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('quick_auth_kill_switch') ?? false) return true;
    final lockType = prefs.getString('lock_type') ?? 'none';
    if (lockType == 'none') return true;

    if (lockType == 'app_pin') {
      if (!context.mounted) return false;
      return _verifyPin(context, prefs);
    }

    try {
      return await LocalAuthentication().authenticate(
        localizedReason: localizedReason,
        options: AuthenticationOptions(
          biometricOnly: lockType == 'biometric',
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _verifyPin(
      BuildContext context, SharedPreferences prefs) async {
    final savedPin = prefs.getString('app_pin') ?? '';
    final colors = context.appColors;
    String pin = '';
    bool wrongPin = false;

    final result = await appShowModalBottomSheet<bool>(
      context: context,
      backgroundColor: colors.surface1,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.md))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final mColors = ctx.appColors;

          void handleDigit(String digit) {
            setModalState(() {
              wrongPin = false;
              if (pin.length < 4) pin += digit;
            });
          }

          void handleConfirm() {
            if (pin.length != 4) return;
            if (pin == savedPin) {
              Navigator.pop(ctx, true);
            } else {
              setModalState(() {
                wrongPin = true;
                pin = '';
              });
            }
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
                20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: mColors.textMuted,
                            borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Text('PIN Girin',
                    style: TextStyle(
                        color: mColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                    wrongPin ? 'Yanlış PIN, tekrar deneyin' : 'Devam etmek için PIN\'inizi girin',
                    style: TextStyle(
                        color: wrongPin ? mColors.error : mColors.textSecondary,
                        fontSize: 13)),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                      4,
                      (i) => Container(
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: pin.length > i
                                  ? mColors.primary
                                  : mColors.surface2,
                            ),
                          )),
                ),
                const SizedBox(height: 24),
                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 3,
                  childAspectRatio: 1.0,
                  children: [
                    ...List.generate(
                        9,
                        (i) => _GatePinButton(
                              label: '${i + 1}',
                              onTap: () => handleDigit('${i + 1}'),
                            )),
                    _GatePinButton(
                        label: '⌫',
                        onTap: () {
                          setModalState(() {
                            wrongPin = false;
                            if (pin.isNotEmpty) {
                              pin = pin.substring(0, pin.length - 1);
                            }
                          });
                        }),
                    _GatePinButton(label: '0', onTap: () => handleDigit('0')),
                    _GatePinConfirmButton(
                      enabled: pin.length == 4,
                      onTap: handleConfirm,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('İptal',
                      style: TextStyle(color: mColors.textSecondary)),
                ),
              ],
            ),
          );
        },
      ),
    );

    return result ?? false;
  }
}

class _GatePinButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _GatePinButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: colors.surface2,
          shape: BoxShape.circle,
          border: Border.all(color: colors.hairline),
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _GatePinConfirmButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _GatePinConfirmButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.curve,
        margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: enabled ? colors.primary : colors.surface2,
          shape: BoxShape.circle,
          border: Border.all(
              color: enabled ? colors.primary : colors.hairline),
        ),
        child: Center(
          child: Icon(Icons.check_rounded,
              color: enabled ? Colors.white : colors.textMuted, size: 24),
        ),
      ),
    );
  }
}
