/// Proxmox'un eski tekli-sunucu ayarları için SharedPreferences anahtarları —
/// çoklu-sunucu JSON'u (`proxmox_servers`) yokken devreye giren geriye dönük
/// uyumluluk yolu (bkz. proxmox_provider.dart init(), proxmox_connection_screen.dart
/// _save()). Bu sınıfın geri kalanı (uygulama adı/sürümü, API zaman aşımları,
/// yenileme sıklıkları, AdGuard/UPS/tema/bildirim anahtarları) hiçbir yerde
/// kullanılmadığı doğrulanıp kaldırıldı.
class AppConstants {
  AppConstants._(); // instantiation engelle

  static const String keyProxmoxHost = 'proxmox_host';
  static const String keyProxmoxPort = 'proxmox_port';
  static const String keyProxmoxTokenId = 'proxmox_token_id';
  static const String keyProxmoxTokenSecret = 'proxmox_token_secret';
}
