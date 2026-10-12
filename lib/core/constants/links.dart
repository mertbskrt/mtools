/// MTools'un kullanıcıya görünen tüm dış adresleri — tek kaynak.
///
/// Kimlik olarak yalnızca MTools, mtools.tr ve contact@mtools.tr kullanılır;
/// kişisel isim ya da kişisel kullanıcı adı içeren adres (ör. GitHub
/// kullanıcı sayfası) buraya eklenmez. Güncelleme mekanizmasının kullandığı
/// teknik GitHub adresleri kullanıcıya gösterilmediği için burada değil,
/// update_service.dart / release_history_service.dart içinde durur.
class MToolsLinks {
  MToolsLinks._();

  static const website = 'https://mtools.tr';
  static const websiteLabel = 'mtools.tr';

  /// mtools.tr ana sayfasından ve gizlilik sayfasının kendisinden doğrulandı
  /// (2026-10-12). Kullanım koşulları sayfası henüz yok; yayınlanınca buraya
  /// eklenip Hakkında → YASAL bölümüne bir satır olarak bağlanacak.
  static const privacy = 'https://mtools.tr/gizlilik/';
  static const privacyLabel = 'mtools.tr/gizlilik';

  static const contactEmail = 'contact@mtools.tr';

  /// Uygulama içi geri bildirim formu (bkz. feedback_service.dart).
  static const feedbackEndpoint = 'https://mtools.tr/api/uygulama';
}
