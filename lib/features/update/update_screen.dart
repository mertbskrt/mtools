import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/mtools_mark.dart';
import '../../core/theme/design_widgets.dart';
import '../../core/utils/app_transitions.dart';
import '../dashboard/error_log_service.dart';
import 'update_service.dart';
import 'update_manifest.dart';
import 'update_installer.dart';
import 'release_history_screen.dart';
import 'release_notes_lite.dart';

const _kLastCheckedKey = 'update_last_checked_at';

/// Ayarlar'daki "Güncellemeler" satırından açılan, kendi başına bir sayfa —
/// eskiden bu satıra dokununca doğrudan kontrol edilip sonuç bir SnackBar/
/// AlertDialog ile gösteriliyordu (bkz. settings_screen.dart'taki eski
/// _UpdateSettingsCard). Kontrol/indirme/kurulum mantığı (UpdateService,
/// UpdateInstaller, SignatureVerifier) DEĞİŞMEDİ — sadece görsel çerçeve.
class UpdateScreen extends StatefulWidget {
  const UpdateScreen({super.key});

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  final _installer = UpdateInstaller();

  String _version = '';
  DateTime? _lastChecked;

  bool _checking = false;
  bool _checkFailed = false;
  UpdateCheckResult? _result;

  int? _apkSizeBytes;

  bool _downloading = false;
  double _progress = 0;
  String? _installError;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadLastChecked();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _version = info.version);
  }

  Future<void> _loadLastChecked() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_kLastCheckedKey);
    if (ms != null && mounted) {
      setState(() => _lastChecked = DateTime.fromMillisecondsSinceEpoch(ms));
    }
  }

  Future<void> _persistLastChecked(DateTime t) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastCheckedKey, t.millisecondsSinceEpoch);
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _checkFailed = false;
      _installError = null;
      _apkSizeBytes = null;
    });

    final now = DateTime.now();
    try {
      final result = await UpdateService().check();
      await _persistLastChecked(now);
      if (!mounted) return;
      setState(() {
        _checking = false;
        _result = result;
        _lastChecked = now;
      });
      if (result.updateAvailable && result.manifest != null) {
        _fetchSize(result.manifest!.apkUrl);
      }
    } catch (e) {
      await ErrorLogService().log(
        type: ErrorLogType.connection,
        message: 'Güncelleme kontrolü başarısız',
        detail: e.toString(),
      );
      await _persistLastChecked(now);
      if (!mounted) return;
      setState(() {
        _checking = false;
        _checkFailed = true;
        _result = null;
        _lastChecked = now;
      });
    }
  }

  Future<void> _fetchSize(String apkUrl) async {
    final size = await UpdateService().fetchApkSize(apkUrl);
    if (mounted) setState(() => _apkSizeBytes = size);
  }

  Future<void> _install(UpdateManifest manifest) async {
    setState(() {
      _downloading = true;
      _installError = null;
      _progress = 0;
    });
    try {
      await _installer.downloadAndInstall(
        manifest,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      // Android paket yükleyicisi açıldı — akışın geri kalanı OS'e ait.
      if (mounted) setState(() => _downloading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _installError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  String _formatLastChecked(DateTime t) {
    final now = DateTime.now();
    final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    if (sameDay(now, t)) return 'bugün $hm';
    if (sameDay(now.subtract(const Duration(days: 1)), t)) return 'dün $hm';
    return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year} $hm';
  }

  String _formatSize(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final manifest = _result?.manifest;
    final hasUpdate = _result?.updateAvailable == true && manifest != null;
    final mandatory = _result?.mandatory == true;

    return PopScope(
      canPop: !mandatory,
      child: Scaffold(
        backgroundColor: colors.bgDark,
        appBar: AppBar(
          backgroundColor: colors.bgDark,
          elevation: 0,
          automaticallyImplyLeading: !mandatory,
          leading: mandatory
              ? null
              : IconButton(
                  icon: Icon(Icons.arrow_back_ios_new,
                      color: colors.textPrimary, size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
          title: Text('Güncellemeler',
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          actions: mandatory
              ? null
              : [
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: colors.textMuted),
                    color: colors.bgCard,
                    onSelected: (v) {
                      if (v == 'history') {
                        Navigator.push(
                          context,
                          AppTransitions.slideFade(const ReleaseHistoryScreen()),
                        );
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'history',
                        child: Text('Sürüm Geçmişi · Release History',
                            style: TextStyle(color: colors.textPrimary)),
                      ),
                    ],
                  ),
                ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
          child: Column(
            children: [
              const SizedBox(height: 12),
              const MtoolsMark(size: 72),
              const SizedBox(height: 14),
              Text(
                'MTools',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 24),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surface1,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: colors.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _version.isNotEmpty
                          ? 'Şu an v$_version kullanıyorsunuz'
                          : 'Sürüm bilgisi yükleniyor...',
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _lastChecked != null
                          ? 'Son kontrol: ${_formatLastChecked(_lastChecked!)}'
                          : 'Henüz kontrol edilmedi',
                      style: TextStyle(color: colors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              if (mandatory) ...[
                _StatusBanner(
                  icon: Icons.warning_amber_rounded,
                  color: colors.warning,
                  text:
                      'Bu güncelleme zorunludur, devam etmeden önce yüklenmelidir.',
                ),
                const SizedBox(height: 16),
              ],

              _CheckButton(checking: _checking, onTap: _check),

              if (!_checking && _result != null && !hasUpdate) ...[
                const SizedBox(height: 16),
                _StatusBanner(
                  icon: Icons.check_circle_outline,
                  color: colors.info,
                  text: 'Güncel',
                ),
              ],

              if (!_checking && _checkFailed) ...[
                const SizedBox(height: 16),
                _StatusBanner(
                  icon: Icons.error_outline,
                  color: colors.error,
                  text: 'Kontrol edilemedi',
                ),
              ],

              if (hasUpdate) ...[
                const SizedBox(height: 16),
                _UpdateDetailCard(
                  manifest: manifest,
                  sizeBytes: _apkSizeBytes,
                  formatSize: _formatSize,
                  downloading: _downloading,
                  progress: _progress,
                  error: _installError,
                  onInstall: () => _install(manifest),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckButton extends StatefulWidget {
  final bool checking;
  final VoidCallback onTap;
  const _CheckButton({required this.checking, required this.onTap});

  @override
  State<_CheckButton> createState() => _CheckButtonState();
}

class _CheckButtonState extends State<_CheckButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTapDown: widget.checking ? null : (_) => setState(() => _pressed = true),
      onTapUp: widget.checking
          ? null
          : (_) {
              setState(() => _pressed = false);
              widget.onTap();
            },
      onTapCancel: widget.checking ? null : () => setState(() => _pressed = false),
      child: PressableScale(
        pressed: _pressed,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.curve,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: _pressed
                ? colors.primary.withValues(alpha: 0.16)
                : colors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
          ),
          alignment: Alignment.center,
          child: widget.checking
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: colors.primary),
                )
              : Text(
                  'Güncellemeleri Kontrol Et',
                  style: TextStyle(
                      color: colors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold),
                ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _StatusBanner({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: color, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _UpdateDetailCard extends StatelessWidget {
  final UpdateManifest manifest;
  final int? sizeBytes;
  final String Function(int) formatSize;
  final bool downloading;
  final double progress;
  final String? error;
  final VoidCallback onInstall;

  const _UpdateDetailCard({
    required this.manifest,
    required this.sizeBytes,
    required this.formatSize,
    required this.downloading,
    required this.progress,
    required this.error,
    required this.onInstall,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final date = manifest.releaseDate;
    final dateStr =
        '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    final notes = parseReleaseNotesLite(manifest.releaseNotes);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.new_releases_outlined, color: colors.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Yeni sürüm mevcut: v${manifest.latestVersion}',
                  style: TextStyle(
                      color: colors.primary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              dateStr,
              if (sizeBytes != null) formatSize(sizeBytes!),
            ].join(' · '),
            style: TextStyle(color: colors.textMuted, fontSize: 11),
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Bu sürümde neler yeni',
              style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            ...notes.map((note) => _ReleaseNoteLine(note: note, colors: colors)),
          ],
          if (downloading) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.xs),
              child: LinearProgressIndicator(
                value: progress > 0 ? progress : null,
                backgroundColor: colors.bgCardLight,
                valueColor: AlwaysStoppedAnimation(colors.primary),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'İndiriliyor... %${(progress * 100).toInt()}',
              style: TextStyle(color: colors.textMuted, fontSize: 11),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: colors.error.withValues(alpha: 0.3)),
              ),
              child: Text(error!,
                  style: TextStyle(color: colors.error, fontSize: 12)),
            ),
          ],
          const SizedBox(height: 16),
          GestureDetector(
            onTap: downloading ? null : onInstall,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: downloading
                    ? colors.surface2
                    : colors.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              alignment: Alignment.center,
              child: Text(
                downloading ? 'İndiriliyor...' : 'Şimdi Güncelle',
                style: TextStyle(
                    color: downloading ? colors.textMuted : colors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReleaseNoteLine extends StatelessWidget {
  final ReleaseNoteLine note;
  final AppThemeData colors;
  const _ReleaseNoteLine({required this.note, required this.colors});

  @override
  Widget build(BuildContext context) {
    if (note.type == ReleaseNoteLineType.heading) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Text(
          note.text,
          style: TextStyle(
              color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: colors.textMuted,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              note.text,
              style: TextStyle(color: colors.textSecondary, fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
