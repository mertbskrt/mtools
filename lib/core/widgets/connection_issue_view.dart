/// Bir servise (Proxmox/AdGuard/UPS/Terminal) internet varken erişilemediğinde
/// ya da cihazın hiç interneti olmadığında gösterilecek durumu belirtir —
/// [privateNetwork]/[tailscale]/[generic], [ConnectionTarget]'tan (bkz.
/// core/utils/connection_target.dart) türetilir; [noInternet] cihazın kendi
/// bağlantısı için ayrı bir sinyaldir.
enum ConnectionIssueKind {
  /// Hedef özel/iç ağ IP'si — kullanıcı muhtemelen dış ağda/VPN'siz,
  /// servis çökmemiş olabilir.
  privateNetwork,

  /// Hedef Tailscale adresi — Tailscale bu cihazda bağlı olmayabilir.
  tailscale,

  /// Hedef dış adres/alan adı — servisin kendisiyle ilgili gerçek bir
  /// sorun olma ihtimali daha yüksek.
  generic,

  /// Cihazın kendisi hiç internete bağlı değil — hangi sunucu olduğu
  /// önemsiz, bu yüzden [connectionIssueCopy] bu durumda serviceName/host'u
  /// yok sayar.
  noInternet,
}

/// [kind]/[serviceName]/[host]'a göre başlık ve açıklama metnini üretir —
/// tüm ekranlar (tam ekran görünümler, UPS'in kompakt banner'ı, Terminal'in
/// kendi hata görünümü) bu tek fonksiyondan beslenir; Türkçe kopya tek
/// yerde tutulur, hiçbir yerde tekrarlanmaz.
(String title, String message) connectionIssueCopy(
  ConnectionIssueKind kind,
  String serviceName,
  String host,
) {
  switch (kind) {
    case ConnectionIssueKind.privateNetwork:
      return (
        'İç ağa erişilemiyor',
        'İnternet bağlantınız var ancak $serviceName iç IP adresi ($host) '
            'üzerinden yanıt vermiyor. İç ağınızda olduğunuza emin misiniz? '
            'Dışarıdaysanız VPN (Tailscale) bağlantınızı kontrol edin.',
      );
    case ConnectionIssueKind.tailscale:
      return (
        'Tailscale ağına erişilemiyor',
        'İnternet bağlantınız var ancak $serviceName Tailscale adresi '
            '($host) üzerinden yanıt vermiyor. Tailscale\'in bu cihazda '
            'bağlı olduğundan emin olun.',
      );
    case ConnectionIssueKind.generic:
      return (
        '$serviceName sunucusuna bağlanılamıyor',
        'Ağ bağlantınızı kontrol edin',
      );
    case ConnectionIssueKind.noInternet:
      return (
        'İnternet Bağlantınız Yok',
        'Cihazınızın internet bağlantısı olmadan sunuculara bağlanılamaz.',
      );
  }
}
