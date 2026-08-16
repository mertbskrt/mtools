import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_theme.dart';
import 'release_history_service.dart';
import 'release_notes_lite.dart';

/// UpdateScreen'in sağ üst 3-nokta menüsünden ("Sürüm Geçmişi") açılan
/// ekran — mtools-releases reposundaki TÜM geçmiş sürümleri GitHub'ın
/// public REST API'sinden çeker (bkz. ReleaseHistoryService, 1 saatlik
/// önbellek). Uygulamada henüz bir yerelleştirme altyapısı olmadığı için
/// (Locale kontrolü yok) TR/EN aynı satırda birlikte gösteriliyor, cihaz
/// diline bakılmıyor — release notes'un kendisi hariç, o GitHub'dan geldiği
/// gibi (genelde sadece Türkçe) gösteriliyor.
class ReleaseHistoryScreen extends StatefulWidget {
  const ReleaseHistoryScreen({super.key});

  @override
  State<ReleaseHistoryScreen> createState() => _ReleaseHistoryScreenState();
}

class _ReleaseHistoryScreenState extends State<ReleaseHistoryScreen> {
  final _service = ReleaseHistoryService();

  bool _loading = true;
  bool _failed = false;
  List<GithubReleaseInfo> _releases = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final releases = await _service.fetch(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _releases = releases;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.bgDark,
      appBar: AppBar(
        backgroundColor: colors.bgDark,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: colors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Sürüm Geçmişi · Release History',
          style: TextStyle(
              color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: colors.textSecondary),
            onPressed: _loading ? null : () => _load(forceRefresh: true),
          ),
        ],
      ),
      body: _buildBody(colors),
    );
  }

  Widget _buildBody(AppThemeData colors) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary),
      );
    }

    if (_failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: colors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: colors.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: colors.error, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Sürüm geçmişi şu an yüklenemedi.\nRelease history unavailable right now.',
                    style: TextStyle(
                        color: colors.error, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_releases.isEmpty) {
      return Center(
        child: Text(
          'Henüz yayınlanmış bir sürüm yok. · No releases yet.',
          style: TextStyle(color: colors.textMuted, fontSize: 13),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      itemCount: _releases.length,
      itemBuilder: (context, index) {
        final release = _releases[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _ReleaseCard(release: release, dateText: _formatDate(release.publishedAt))
              .animate()
              .fadeIn(delay: (index * 40).ms, duration: 260.ms),
        );
      },
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  final GithubReleaseInfo release;
  final String dateText;
  const _ReleaseCard({required this.release, required this.dateText});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final lines = parseReleaseNotesLite(release.body);

    return Container(
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
                ),
                child: Text(release.tagName,
                    style: TextStyle(
                        color: colors.primary, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Text(dateText, style: TextStyle(color: colors.textMuted, fontSize: 11)),
            ],
          ),
          if (lines.isEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Bu sürüm için not eklenmemiş. · No notes for this release.',
              style: TextStyle(color: colors.textMuted, fontSize: 12),
            ),
          ] else ...[
            const SizedBox(height: 14),
            ...lines.map((line) => _ReleaseNoteLineWidget(line: line, colors: colors)),
          ],
        ],
      ),
    );
  }
}

class _ReleaseNoteLineWidget extends StatelessWidget {
  final ReleaseNoteLine line;
  final AppThemeData colors;
  const _ReleaseNoteLineWidget({required this.line, required this.colors});

  @override
  Widget build(BuildContext context) {
    switch (line.type) {
      case ReleaseNoteLineType.heading:
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Text(
            line.text,
            style: TextStyle(
                color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
          ),
        );
      case ReleaseNoteLineType.bullet:
        // update_screen.dart'taki _UpdateDetailCard.notes ile aynı bullet
        // deseni — yeni bir liste/kart dili icat edilmiyor.
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
                  line.text,
                  style: TextStyle(color: colors.textSecondary, fontSize: 13, height: 1.5),
                ),
              ),
            ],
          ),
        );
      case ReleaseNoteLineType.paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            line.text,
            style: TextStyle(color: colors.textSecondary, fontSize: 13, height: 1.5),
          ),
        );
    }
  }
}
