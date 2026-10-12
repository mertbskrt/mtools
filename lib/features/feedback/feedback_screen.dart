import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/crash_reporter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_widgets.dart';
import '../../widgets/mtools_loader.dart';
import 'feedback_service.dart';
import '../../core/constants/links.dart';

/// Ayarlar → "Geri bildirim gönder". Hata ekranındaki "Bu hatayı bildir"
/// butonu da bunu [initialType] = hata, [includeLogInitially] = true ve
/// ekran adı/hata kodu yazılı [initialMessage] ile açar.
///
/// API anahtarı derlemede verilmediyse (bkz. [kMtoolsAppKey]) form yerine
/// e-posta seçeneği gösterilir.
class FeedbackScreen extends StatefulWidget {
  final FeedbackType initialType;
  final String initialMessage;
  final bool includeLogInitially;
  final FeedbackService? service;

  const FeedbackScreen({
    super.key,
    this.initialType = FeedbackType.oneri,
    this.initialMessage = '',
    this.includeLogInitially = false,
    this.service,
  });

  /// Hata ekranındaki "Bu hatayı bildir": tür hata, günlük işaretli, mesajda
  /// ekran adı ve hata kodu (ör. "Ekran: Sistem · Kod: SYS-7F3A").
  factory FeedbackScreen.forError(ErrorOrigin origin,
          {FeedbackService? service}) =>
      FeedbackScreen(
        initialType: FeedbackType.hata,
        includeLogInitially: true,
        initialMessage:
            'Ekran: ${origin.screenName} · Kod: ${origin.code}\n\n',
        service: service,
      );

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  static const _minMessage = 10;
  static const _maxMessage = 3000;
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  late final FeedbackService _service = widget.service ?? FeedbackService();
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  late final TextEditingController _messageCtrl =
      TextEditingController(text: widget.initialMessage);
  late FeedbackType _type = widget.initialType;
  late bool _includeLog = widget.includeLogInitially;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) return;
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _sending = true);
    final result = await _service.send(
      type: _type,
      name: _nameCtrl.text,
      email: _emailCtrl.text,
      message: _messageCtrl.text,
      includeLog: _includeLog,
    );
    if (!mounted) return;

    switch (result) {
      case FeedbackSent():
        final colors = context.appColors;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text(
              'Mesajınız alındı. E-posta adresinize bir onay gönderdik.'),
          backgroundColor: colors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md)),
        ));
        Navigator.of(context).pop();
        return;
      case FeedbackRejected(:final message):
        _error = message;
      case FeedbackRateLimited():
        _error = 'Çok fazla deneme yapıldı, lütfen biraz sonra tekrar deneyin.';
      case FeedbackNetworkError():
        _error = 'Gönderilemedi. İnternet bağlantınızı kontrol edin ya da '
            '${MToolsLinks.contactEmail} adresine yazın.';
    }
    setState(() => _sending = false);
  }

  Future<void> _sendMail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: MToolsLinks.contactEmail,
      queryParameters: {
        'subject': 'MTools Geri Bildirim',
        if (widget.initialMessage.isNotEmpty) 'body': widget.initialMessage,
      },
    );
    var launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Aşağıda panoya kopyalama ile ele alınıyor.
    }
    if (launched || !mounted) return;
    await Clipboard.setData(const ClipboardData(text: MToolsLinks.contactEmail));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          const Text('Mail uygulaması bulunamadı. E-posta adresi kopyalandı.'),
      backgroundColor: context.appColors.warning,
      behavior: SnackBarBehavior.floating,
    ));
  }

  InputDecoration _decoration(AppThemeData colors, String label,
      {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: colors.textSecondary, fontSize: 13),
      hintStyle: TextStyle(color: colors.textMuted, fontSize: 13),
      counterStyle: TextStyle(color: colors.textMuted, fontSize: 11),
      filled: true,
      fillColor: colors.surface2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: colors.primary, width: 1.5),
      ),
    );
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
        title: Text('Geri Bildirim',
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
      ),
      body: _service.isConfigured ? _buildForm(colors) : _buildMailOnly(colors),
    );
  }

  Widget _buildMailOnly(AppThemeData colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mail_outline_rounded, color: colors.textMuted, size: 48),
            const SizedBox(height: 16),
            Text(
              'Geri bildirim için ${MToolsLinks.contactEmail} adresine yazın.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _sendMail,
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('E-posta gönder'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(AppThemeData colors) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        children: [
          const SectionLabel('TÜR'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in FeedbackType.values)
                ChoiceChip(
                  label: Text(t.label),
                  selected: _type == t,
                  onSelected: _sending ? null : (_) => setState(() => _type = t),
                  selectedColor: colors.primary.withValues(alpha: 0.18),
                  labelStyle: TextStyle(
                    color: _type == t ? colors.primary : colors.textSecondary,
                    fontSize: 13,
                    fontWeight: _type == t ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _nameCtrl,
            enabled: !_sending,
            textCapitalization: TextCapitalization.words,
            style: TextStyle(color: colors.textPrimary, fontSize: 14),
            decoration: _decoration(colors, 'Ad (isteğe bağlı)'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _emailCtrl,
            enabled: !_sending,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            style: TextStyle(color: colors.textPrimary, fontSize: 14),
            decoration: _decoration(colors, 'E-posta',
                hint: 'Yanıt bu adrese gönderilir'),
            validator: (v) {
              final value = v?.trim() ?? '';
              if (value.isEmpty) return 'E-posta adresi gerekli';
              if (!_emailPattern.hasMatch(value)) {
                return 'Geçerli bir e-posta adresi girin';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _messageCtrl,
            enabled: !_sending,
            minLines: 5,
            maxLines: 10,
            maxLength: _maxMessage,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(color: colors.textPrimary, fontSize: 14),
            decoration: _decoration(colors, 'Mesaj'),
            validator: (v) {
              final length = v?.trim().length ?? 0;
              if (length < _minMessage) {
                return 'Mesaj en az $_minMessage karakter olmalı';
              }
              return null;
            },
          ),
          const SizedBox(height: 4),
          CheckboxListTile(
            value: _includeLog,
            onChanged: _sending
                ? null
                : (v) => setState(() => _includeLog = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: colors.primary,
            title: Text('Hata günlüğünü ekle',
                style: TextStyle(color: colors.textPrimary, fontSize: 14)),
            subtitle: Text(
                'Günlükte sunucu adları ve IP adresleri bulunabilir.',
                style: TextStyle(color: colors.textMuted, fontSize: 12)),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: colors.error.withValues(alpha: 0.3)),
              ),
              child: Text(_error!,
                  style: TextStyle(color: colors.error, fontSize: 13)),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _sending ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    colors.primary.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              child: _sending
                  ? const MToolsLoader(size: 18)
                  : const Text('Gönder',
                      style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
