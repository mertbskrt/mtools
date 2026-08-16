import 'package:flutter/material.dart';
import '../services/quick_auth_gate.dart';
import '../theme/app_theme.dart';
import '../utils/app_transitions.dart';

Future<bool> showAppConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  bool isDestructive = true,
  bool requireAuth = false,
  String authReason = 'İşlemi onaylamak için doğrulayın',
}) async {
  final colors = context.appColors;
  final confirmed = await appShowDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      backgroundColor: colors.surface1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      title: Text(title, style: TextStyle(color: colors.textPrimary)),
      content: Text(message,
          style: TextStyle(color: colors.textSecondary, fontSize: 13)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dctx, false),
          child: Text('İptal', style: TextStyle(color: colors.textSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dctx, true),
          child: Text(confirmLabel,
              style: TextStyle(
                  color: isDestructive ? colors.error : colors.primary,
                  fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );

  if (confirmed != true) return false;
  if (!requireAuth) return true;
  if (!context.mounted) return false;
  return QuickAuthGate.verify(context, localizedReason: authReason);
}
