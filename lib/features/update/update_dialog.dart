import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_transitions.dart';
import 'update_installer.dart';
import 'update_manifest.dart';

/// Güncelleme mevcut olduğunda gösterilir. `mandatory` true ise diyalog ne
/// geri tuşuyla ne de dışına dokunularak kapatılabilir — kullanıcı
/// güncellemeden uygulamayı kullanmaya devam edemez.
Future<void> showUpdateDialog(
  BuildContext context, {
  required UpdateManifest manifest,
  required bool mandatory,
}) {
  return appShowDialog(
    context: context,
    barrierDismissible: !mandatory,
    builder: (_) => PopScope(
      canPop: !mandatory,
      child: UpdateDialog(manifest: manifest, mandatory: mandatory),
    ),
  );
}

class UpdateDialog extends StatefulWidget {
  final UpdateManifest manifest;
  final bool mandatory;

  const UpdateDialog({
    super.key,
    required this.manifest,
    required this.mandatory,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  final _installer = UpdateInstaller();
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  Future<void> _update() async {
    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0;
    });
    try {
      await _installer.downloadAndInstall(
        widget.manifest,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      // Android paket yükleyicisi açıldı — diyaloğun görevi bitti.
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final m = widget.manifest;

    return AlertDialog(
      backgroundColor: colors.bgCard,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      title: Row(
        children: [
          Icon(Icons.system_update_rounded, color: colors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Güncelleme Var — v${m.latestVersion}',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.mandatory)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: colors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border:
                      Border.all(color: colors.warning.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: colors.warning, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Bu güncelleme zorunludur, devam etmeden önce yüklenmelidir.',
                        style: TextStyle(color: colors.warning, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            if (m.releaseNotes.isNotEmpty)
              Text(
                m.releaseNotes,
                style: TextStyle(
                    color: colors.textSecondary, fontSize: 13, height: 1.5),
              ),
            if (_downloading) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.xs),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  backgroundColor: colors.bgCardLight,
                  valueColor: AlwaysStoppedAnimation(colors.primary),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'İndiriliyor... %${(_progress * 100).toInt()}',
                style: TextStyle(color: colors.textMuted, fontSize: 11),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border:
                      Border.all(color: colors.error.withValues(alpha: 0.3)),
                ),
                child: Text(_error!,
                    style: TextStyle(color: colors.error, fontSize: 12)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!widget.mandatory && !_downloading)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Sonra', style: TextStyle(color: colors.textSecondary)),
          ),
        TextButton(
          onPressed: _downloading ? null : _update,
          child: Text(
            _downloading ? 'İndiriliyor...' : 'Şimdi Güncelle',
            style: TextStyle(
                color: colors.primary, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
