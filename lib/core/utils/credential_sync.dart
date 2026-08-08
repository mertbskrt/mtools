/// Bulut senkronuna giden sunucu listelerinde (SSH/Proxmox/NUT/AdGuard)
/// yapı alanlarını (isim/host/port/vb.) cihazlar arası senkron tutarken,
/// kimlik bilgisi alanlarını (şifre/token) hiçbir zaman cloud'a yazmamak
/// ve cloud'dan okurken de yerel kimlik bilgisini kaybetmemek için ortak
/// birleştirme mantığı.
///
/// Önemli ayrım: boş kimlik bilgisi HER ZAMAN "eksik" anlamına gelmez —
/// bazı kurulumlar (anonim NUT upsd, auth'suz AdGuard Home) bilinçli
/// olarak kimlik bilgisiz çalışır. Bu yüzden [stripCredentialFields]
/// kaydederken `hasCredentials` bayrağını (kimlik bilgisi o an doluydu mu)
/// yapı verisiyle birlikte saklar; [mergeCloudStructureWithLocalCredentials]
/// "kimlik bilgisi gerekli" durumunu sadece `hasCredentials == true` VE
/// yerelde de boşsa true döner — bilinçli boş bırakılmış girişler hiç
/// işaretlenmez, sorgu normal atılır.
library;

/// Cloud'dan gelen yapı verisiyle local'de duran kimlik bilgilerini
/// `name` alanına göre eşleştirerek birleştirir. Her girişe, tüketicinin
/// UI'da "kimlik bilgisi gerekli" uyarısı gösterip göstermeyeceğini
/// belirleyen bir `needsCredentials` (bool) alanı eklenir.
///
/// - Hem cloud hem local'de olan bir isim: yapı alanları cloud'dan gelir,
///   [credentialFields] local'deki değerle doldurulur (yoksa boş string).
/// - Sadece cloud'da olan bir isim (yeni cihaz senaryosu): [credentialFields]
///   boş döner; `needsCredentials`, cloud'daki `hasCredentials` bayrağına
///   göre belirlenir (bilinçli boş bırakılmışsa false kalır).
/// - Sadece local'de olan bir isim (henüz cloud'a hiç yazılmamış): aynen
///   korunur, `needsCredentials` her zaman false (yerel veri zaten
///   eksiksiz/düzenlenebilir, cloud senkronu bekleyen bir şey yok).
List<Map<String, dynamic>> mergeCloudStructureWithLocalCredentials({
  required List<Map<String, dynamic>> cloudList,
  required List<Map<String, dynamic>> localList,
  required List<String> credentialFields,
}) {
  final localByName = <String, Map<String, dynamic>>{
    for (final e in localList) (e['name'] as String? ?? ''): e,
  };
  final cloudNames = <String>{};
  final merged = <Map<String, dynamic>>[];

  for (final cloudEntry in cloudList) {
    final name = cloudEntry['name'] as String? ?? '';
    cloudNames.add(name);
    final local = localByName[name];
    final entry = Map<String, dynamic>.from(cloudEntry);
    for (final field in credentialFields) {
      final localValue = local?[field] as String?;
      // ÖNEMLİ: local'de yoksa cloud'un KENDİ değerini at ma — cloud bu
      // alanı normalde hiç taşımaz (yeni kayıtlar hep sanitize edilir),
      // ama temizlik (security_cleanup_service) henüz çalışmamış eski
      // formatlı veride veya bu cihazda local'in taze/boş olduğu bir
      // durumda (yeniden kurulum vb.) cloud'da hâlâ gerçek kimlik bilgisi
      // durabilir — onu sessizce silmek yerine burada geri kazanılır.
      final cloudValue = cloudEntry[field] as String?;
      entry[field] = (localValue != null && localValue.isNotEmpty)
          ? localValue
          : (cloudValue ?? '');
    }
    final hadCredentials = cloudEntry['hasCredentials'] as bool? ?? false;
    final stillEmpty =
        credentialFields.any((f) => (entry[f] as String? ?? '').isEmpty);
    entry['needsCredentials'] = hadCredentials && stillEmpty;
    merged.add(entry);
  }

  for (final local in localList) {
    final name = local['name'] as String? ?? '';
    if (!cloudNames.contains(name)) {
      final entry = Map<String, dynamic>.from(local);
      entry['needsCredentials'] = false;
      merged.add(entry);
    }
  }

  return merged;
}

/// Verilen kimlik bilgisi alanlarını boş string'e çevirip `hasCredentials`
/// bayrağını (temizlemeden ÖNCE hepsi doluydu mu) ekleyerek yeni bir kopya
/// döner — cloud'a yazmadan önce kullanılır. `hasCredentials == false`,
/// bu girişin bilinçli olarak kimlik bilgisiz bırakıldığını (anonim
/// erişim) işaretler; başka bir cihaz bunu "eksik" diye göstermez.
Map<String, dynamic> stripCredentialFields(
  Map<String, dynamic> json,
  List<String> credentialFields,
) {
  final copy = Map<String, dynamic>.from(json);
  final hadCredentials =
      credentialFields.every((f) => (json[f] as String? ?? '').isNotEmpty);
  for (final field in credentialFields) {
    copy[field] = '';
  }
  copy['hasCredentials'] = hadCredentials;
  return copy;
}
