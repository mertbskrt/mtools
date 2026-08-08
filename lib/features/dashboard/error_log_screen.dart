import 'package:flutter/material.dart';
import '../../core/utils/app_transitions.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import 'error_log_service.dart';

class ErrorLogScreen extends StatefulWidget {
  const ErrorLogScreen({super.key});

  @override
  State<ErrorLogScreen> createState() => _ErrorLogScreenState();
}

class _ErrorLogScreenState extends State<ErrorLogScreen> {
  final _service = ErrorLogService();
  ErrorLogType? _filter;

  List<ErrorLogEntry>? _filteredCache;
  ErrorLogType? _lastFilter;

  List<ErrorLogEntry> get _filtered {
    if (_filteredCache != null && _lastFilter == _filter) {
      return _filteredCache!;
    }
    _lastFilter = _filter;
    _filteredCache = _filter == null
        ? _service.logs
        : _service.logs.where((e) => e.type == _filter).toList();
    return _filteredCache!;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.bgDark,
      appBar: AppBar(
        backgroundColor: colors.bgDark,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new,
              color: colors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Hata Günlüğü',
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        actions: [
          // Filtre
          PopupMenuButton<ErrorLogType?>(
            color: colors.bgCard,
            icon: Icon(Icons.filter_list_rounded,
                color: _filter != null ? colors.primary : colors.textMuted),
            onSelected: (v) => setState(() => _filter = v),
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: null,
                child:
                    Text('Tümü', style: TextStyle(color: colors.textPrimary)),
              ),
              ...ErrorLogType.values.map((t) {
                // Bir kez oluştur, iki kez kullan
                final dummy = ErrorLogEntry(
                    id: '', time: DateTime.now(), type: t, message: '');
                return PopupMenuItem(
                  value: t,
                  child: Row(children: [
                    Icon(dummy.icon, color: colors.textMuted, size: 16),
                    const SizedBox(width: 8),
                    Text(dummy.typeLabel,
                        style: TextStyle(color: colors.textPrimary)),
                  ]),
                );
              }),
            ],
          ),
          // Temizle
          IconButton(
            icon: Icon(Icons.delete_sweep_rounded, color: colors.error),
            onPressed: () async {
              final confirm = await appShowDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: colors.bgCard,
                  title: Text('Günlüğü Temizle',
                      style: TextStyle(color: colors.textPrimary)),
                  content: Text('Tüm hata kayıtları silinecek.',
                      style: TextStyle(color: colors.textSecondary)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text('İptal',
                            style: TextStyle(color: colors.textMuted))),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text('Temizle',
                            style: TextStyle(color: colors.error))),
                  ],
                ),
              );
              if (confirm == true) {
                await _service.clear();
                if (!mounted) return;
                _filteredCache = null;
                setState(() {});
              }
            },
          ),
        ],
      ),
      body: _filtered.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline_rounded,
                      color: colors.success, size: 56),
                  const SizedBox(height: 16),
                  Text('Hata kaydı yok',
                      style:
                          TextStyle(color: colors.textSecondary, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text('Sistem sorunsuz çalışıyor.',
                      style: TextStyle(color: colors.textMuted, fontSize: 13)),
                ],
              ),
            )
          : Column(
              children: [
                // Özet bar
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: colors.bgCard,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.history_rounded,
                          color: colors.textMuted, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        '${_filtered.length} kayıt',
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 12),
                      ),
                      const Spacer(),
                      // Tür bazında sayım
                      ...ErrorLogType.values.map((t) {
                        final count =
                            _service.logs.where((e) => e.type == t).length;
                        if (count == 0) return const SizedBox.shrink();
                        // color iki kez çağrılıyor — bir kez hesapla
                        final dummy = ErrorLogEntry(
                            id: '', time: DateTime.now(), type: t, message: '');
                        final c = dummy.color;
                        return Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: c.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                          ),
                          child: Text('$count',
                              style: TextStyle(
                                  color: c,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        );
                      }),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    itemCount: _filtered.length,
                    itemBuilder: (ctx, i) {
                      final entry = _filtered[i];
                      return _LogCard(entry: entry);
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _LogCard extends StatelessWidget {
  final ErrorLogEntry entry;

  const _LogCard({required this.entry});

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inSeconds < 60) return '${diff.inSeconds}sn önce';
    if (diff.inMinutes < 60) return '${diff.inMinutes}dk önce';
    if (diff.inHours < 24) return '${diff.inHours}sa önce';
    return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final color = entry.color;

    return GestureDetector(
      onLongPress: () {
        final text =
            '[${entry.time.toIso8601String()}] ${entry.typeLabel}: ${entry.message}'
            '${entry.detail != null ? '\n${entry.detail}' : ''}';
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Kopyalandı'),
          backgroundColor: colors.success,
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        ));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.bgCard,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(entry.icon, color: color, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(entry.typeLabel,
                            style: TextStyle(
                                color: color,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                      const Spacer(),
                      Text(_formatTime(entry.time),
                          style:
                              TextStyle(color: colors.textMuted, fontSize: 10)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(entry.message,
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                  if (entry.detail != null) ...[
                    const SizedBox(height: 4),
                    Text(entry.detail!,
                        style: TextStyle(color: colors.textMuted, fontSize: 11),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
