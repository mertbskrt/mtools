import 'package:flutter/material.dart';
import '../../core/utils/app_transitions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_widgets.dart';

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  final LocalAuthentication _auth = LocalAuthentication();
  bool _lockEnabled = false;
  bool _biometricAvailable = false;
  String _lockType = 'none';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final canAuth = await _auth.canCheckBiometrics;
    final isSupported = await _auth.isDeviceSupported();
    if (!mounted) return;
    setState(() {
      _lockEnabled = prefs.getBool('lock_enabled') ?? false;
      _lockType = prefs.getString('lock_type') ?? 'none';
      _biometricAvailable = canAuth && isSupported;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('lock_enabled', _lockEnabled);
    await prefs.setString('lock_type', _lockType);
  }

  void _showPinSetup() {
    final colors = context.appColors;
    String pin = '';
    String confirmPin = '';
    bool confirming = false;

    appShowModalBottomSheet(
      context: context,
      backgroundColor: colors.surface1,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.md))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final mColors = ctx.appColors;

          Future<void> handleDigit(String digit) async {
            setModalState(() {
              if (confirming) {
                if (confirmPin.length < 4) confirmPin += digit;
              } else {
                if (pin.length < 4) pin += digit;
              }
            });

            if (!confirming && pin.length == 4) {
              setModalState(() => confirming = true);
            } else if (confirming && confirmPin.length == 4) {
              if (pin == confirmPin) {
                final messenger = ScaffoldMessenger.of(context);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('app_pin', pin);
                if (mounted) setState(() => _lockType = 'app_pin');
                await _save();
                if (context.mounted) {
                  Navigator.pop(ctx);
                  messenger.showSnackBar(
                    SnackBar(
                        content: const Text('PIN kaydedildi'),
                        backgroundColor: mColors.success),
                  );
                }
              } else {
                setModalState(() {
                  confirmPin = '';
                  confirming = false;
                  pin = '';
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: const Text('PIN\'ler eşleşmedi'),
                      backgroundColor: mColors.error),
                );
              }
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
                Text(confirming ? 'PIN\'i Tekrar Girin' : 'Yeni PIN Belirle',
                    style: TextStyle(
                        color: mColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                    confirming
                        ? 'PIN\'i onaylamak için tekrar girin'
                        : '4 haneli bir PIN belirleyin',
                    style:
                        TextStyle(color: mColors.textSecondary, fontSize: 13)),
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
                              color: (confirming ? confirmPin : pin).length > i
                                  ? mColors.primary
                                  : mColors.surface2,
                            ),
                          )),
                ),
                const SizedBox(height: 24),
                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 3,
                  childAspectRatio: 1.5,
                  children: [
                    ...List.generate(
                        9,
                        (i) => _PinButton(
                              label: '${i + 1}',
                              onTap: () => handleDigit('${i + 1}'),
                            )),
                    _PinButton(
                        label: '⌫',
                        onTap: () {
                          setModalState(() {
                            if (confirming && confirmPin.isNotEmpty) {
                              confirmPin = confirmPin.substring(
                                  0, confirmPin.length - 1);
                            } else if (!confirming && pin.isNotEmpty) {
                              pin = pin.substring(0, pin.length - 1);
                            }
                          });
                        }),
                    _PinButton(label: '0', onTap: () => handleDigit('0')),
                    const SizedBox(),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.surface0,
      appBar: AppBar(title: const Text('Uygulama Kilidi')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: BoxDecoration(
              color: colors.surface1,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: colors.hairline),
            ),
            child: SwitchListTile(
              title: Text('Uygulama Kilidi',
                  style: TextStyle(
                      color: colors.textPrimary, fontWeight: FontWeight.w600)),
              subtitle: Text(
                _lockEnabled
                    ? 'Uygulama açılırken doğrulama istenir'
                    : 'Uygulama kilitsiz açılır',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
              value: _lockEnabled,
              activeThumbColor: colors.primary,
              onChanged: (v) async {
                if (v) {
                  final messenger = ScaffoldMessenger.of(context);
                  final isSupported = await _auth.isDeviceSupported();
                  if (!isSupported && context.mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: const Text(
                            'Cihazınızda kayıtlı parmak izi veya şifre bulunamadı. Uygulama PIN\'i kullanabilirsiniz.'),
                        backgroundColor: colors.warning,
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  }
                }
                setState(() {
                  _lockEnabled = v;
                  if (!v) _lockType = 'none';
                });
                _save();
              },
            ),
          ),
          if (_lockEnabled) ...[
            const SizedBox(height: 24),
            const SectionLabel('Kilit Türü'),
            const SizedBox(height: 10),
            if (_biometricAvailable) ...[
              _LockOption(
                icon: Icons.fingerprint,
                title: 'Parmak İzi',
                subtitle: 'Biyometrik doğrulama kullan',
                selected: _lockType == 'biometric',
                onTap: () async {
                  try {
                    final authenticated = await _auth.authenticate(
                      localizedReason: 'Parmak izinizi doğrulayın',
                      options: const AuthenticationOptions(
                        biometricOnly: true,
                        stickyAuth: true,
                      ),
                    );
                    if (authenticated && mounted) {
                      setState(() => _lockType = 'biometric');
                      _save();
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: const Text(
                                'Hata: Cihazda parmak izi kayıtlı değil'),
                            backgroundColor: colors.error),
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
            _LockOption(
              icon: Icons.pin_outlined,
              title: 'PIN / Şifre',
              subtitle: 'Cihaz PIN veya şifresi kullan',
              selected: _lockType == 'pin',
              onTap: () async {
                // local_auth direkt PIN ekranı açamaz, sistem her zaman
                // biyometriği önce sunar. Kullanıcı oradan "PIN kullan"a geçer.
                try {
                  final authenticated = await _auth.authenticate(
                    localizedReason: 'PIN veya şifrenizi girin',
                    options: const AuthenticationOptions(
                      biometricOnly: false,
                      stickyAuth: true,
                      useErrorDialogs: false,
                    ),
                  );
                  if (authenticated && mounted) {
                    setState(() => _lockType = 'pin');
                    _save();
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: const Text(
                              'Hata: Cihazda kayıtlı şifre bulunamadı'),
                          backgroundColor: colors.error),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 8),
            _LockOption(
              icon: Icons.apps_outlined,
              title: 'Uygulama PIN\'i',
              subtitle: '4 haneli PIN belirle',
              selected: _lockType == 'app_pin',
              onTap: () => _showPinSetup(),
            ),
            if (_biometricAvailable) ...[
              const SizedBox(height: 8),
              _LockOption(
                icon: Icons.security,
                title: 'Parmak İzi veya PIN',
                subtitle: 'Her ikisini de kabul et',
                selected: _lockType == 'both',
                onTap: () async {
                  try {
                    final authenticated = await _auth.authenticate(
                      localizedReason: 'Doğrulama yapın',
                      options: const AuthenticationOptions(
                        biometricOnly: false,
                        stickyAuth: true,
                      ),
                    );
                    if (authenticated && mounted) {
                      setState(() => _lockType = 'both');
                      _save();
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: const Text(
                                'Hata: Cihazda kayıtlı doğrulama yöntemi bulunamadı'),
                            backgroundColor: colors.error),
                      );
                    }
                  }
                },
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _LockOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _LockOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? colors.primary : colors.hairline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: selected
                    ? colors.primary.withValues(alpha: 0.15)
                    : colors.surface2,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon,
                  color: selected ? colors.primary : colors.textMuted,
                  size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: selected ? colors.primary : colors.textPrimary,
                          fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style:
                          TextStyle(color: colors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, color: colors.primary, size: 20),
          ],
        ),
      ),
    );
  }
}

class _PinButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PinButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.sm),
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
