import 'dart:io';

/// Bir servise bağlanılamadığında hedef adresin "nerede" olduğunu belirtir —
/// bu, kullanıcının yanlış ağda mı yoksa servisin gerçekten çökmüş mü
/// olduğunu ayırt etmek için kullanılır (bkz. [classifyHost]).
enum ConnectionTarget {
  /// RFC1918 özel ağ aralığı (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16) —
  /// kullanıcı muhtemelen dış ağda/VPN'siz, servis çökmemiş olabilir.
  privateNetwork,

  /// Tailscale CGNAT aralığı (100.64.0.0/10) — Tailscale bu cihazda bağlı
  /// değil ya da servis tarafında çalışmıyor olabilir.
  tailscale,

  /// Herkese açık IP veya çözümlenmemiş bir alan adı — gerçekten servisin
  /// kendisi ile ilgili bir sorun olma ihtimali daha yüksek.
  external,
}

/// [hostOrUrl] içindeki host'u (şema/port varsa ayıklayarak) IPv4 aralığına
/// göre sınıflandırır. Saf bir fonksiyondur — DNS çözümlemesi yapmaz; bir
/// hostname verilmişse (IP değilse) doğrudan [ConnectionTarget.external]
/// döner. IPv6 adresleri de kapsam dışıdır (bu sınıflandırma yalnızca
/// IPv4 RFC1918 ve Tailscale CGNAT aralıkları için tanımlıdır) ve
/// [ConnectionTarget.external] olarak değerlendirilir.
ConnectionTarget classifyHost(String hostOrUrl) {
  final host = _extractHost(hostOrUrl);
  final addr = InternetAddress.tryParse(host);
  if (addr == null || addr.type != InternetAddressType.IPv4) {
    return ConnectionTarget.external;
  }

  final octets = addr.rawAddress;
  final a = octets[0];
  final b = octets[1];

  // RFC1918: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
  if (a == 10) return ConnectionTarget.privateNetwork;
  if (a == 172 && b >= 16 && b <= 31) return ConnectionTarget.privateNetwork;
  if (a == 192 && b == 168) return ConnectionTarget.privateNetwork;

  // Tailscale CGNAT aralığı: 100.64.0.0 – 100.127.255.255 (100.64.0.0/10)
  if (a == 100 && b >= 64 && b <= 127) return ConnectionTarget.tailscale;

  return ConnectionTarget.external;
}

/// "host", "host:port", "scheme://host:port" biçimlerinin herhangi birinden
/// çıplak host'u ayıklar.
String _extractHost(String input) {
  var s = input.trim();
  if (s.contains('://')) {
    final uri = Uri.tryParse(s);
    if (uri != null && uri.host.isNotEmpty) return uri.host;
  }
  // Şema yok. "host:port" olabilir — ama IPv6 literalleri birden fazla ':'
  // içerir, onlara dokunma (zaten external'a düşecekler).
  final colonCount = ':'.allMatches(s).length;
  if (colonCount == 1) {
    s = s.substring(0, s.indexOf(':'));
  }
  return s;
}
