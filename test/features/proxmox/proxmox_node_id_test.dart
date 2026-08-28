import 'package:flutter_test/flutter_test.dart';
import 'package:mtools/features/proxmox/proxmox_provider.dart';

void main() {
  group('composeNodeId / nodeNameFromId / hostFromId — round-trip', () {
    test('composeNodeId + nodeNameFromId geri çıplak adı verir', () {
      final id = composeNodeId('192.168.1.10', 'pve');
      expect(nodeNameFromId(id), 'pve');
    });

    test('composeNodeId + hostFromId geri host\'u verir', () {
      final id = composeNodeId('192.168.1.10', 'pve');
      expect(hostFromId(id), '192.168.1.10');
    });

    test('farklı host/node kombinasyonlarında round-trip', () {
      for (final combo in [
        ('proxmox.example.com', 'node-01'),
        ('10.0.0.5', 'pve2'),
        ('fe80::1', 'pve'), // IPv6 host — ayraçla çakışma riski yok
      ]) {
        final (host, node) = combo;
        final id = composeNodeId(host, node);
        expect(nodeNameFromId(id), node, reason: 'host=$host node=$node');
        expect(hostFromId(id), host, reason: 'host=$host node=$node');
      }
    });

    test('nodeNameFromId — ayraç yoksa (eski çıplak isim) girdiyi olduğu gibi döner', () {
      expect(nodeNameFromId('pve'), 'pve');
      expect(nodeNameFromId(''), '');
    });

    test('hostFromId — ayraç yoksa (eski çıplak isim) boş string döner', () {
      expect(hostFromId('pve'), '');
    });
  });

  group('matchNodeKey — tam eşleşme', () {
    test('storedId map\'te birebir varsa direkt onu döner', () {
      final id = composeNodeId('192.168.1.10', 'pve');
      final map = {id: 1, 'pve2': 2};
      expect(matchNodeKey(map, id), id);
    });
  });

  group('matchNodeKey — eski-format düşümü (YÖN A: eski çıplak isim sorgusu, yeni bileşik map)', () {
    test('map YENİ bileşik kimliklerle anahtarlanmış, storedId ESKİ çıplak isim', () {
      // _serviceFor / hostForNode / isDeliberateOff gibi okuma noktalarının
      // gerçek senaryosu: bu turda taze doldurulan map (composite id'lerle),
      // ama sorgu eski (yükseltme öncesi) kayıtlı bir bare name.
      final id = composeNodeId('192.168.1.10', 'pve');
      final map = {id: 'serviceA'};
      expect(matchNodeKey(map, 'pve'), id);
    });
  });

  group('matchNodeKey — eski-format düşümü (YÖN B: yeni bileşik sorgu, eski çıplak map)', () {
    test('map hâlâ ESKİ çıplak isimlerle anahtarlanmış, storedId YENİ bileşik kimlik', () {
      // _expandedNodes/_sectionVisibility/_deliberateOffNodes gibi
      // yükseltme öncesinden kalma, henüz yeniden yazılmamış yerel state.
      // Bu, matchNodeKey'in ilk (hatalı) implementasyonunun YANLIŞ yaptığı
      // yöndü — sadece map anahtarlarını normalize edip storedId'yi
      // olduğu gibi bırakıyordu, bu yüzden asla eşleşmiyordu.
      final map = {'pve': true};
      final newId = composeNodeId('192.168.1.10', 'pve');
      expect(matchNodeKey(map, newId), 'pve');
    });

    test('host DEĞİŞSE bile (farklı host önekiyle) aynı node adı eşleşir', () {
      // Gerçek dünya senaryosu: kullanıcı sunucunun IP'sini değiştirdi,
      // node aynı ama bileşik kimliğin host kısmı artık farklı.
      final map = {'pve': 'eski-tercih'};
      final idAfterHostChange = composeNodeId('10.0.0.99', 'pve');
      expect(matchNodeKey(map, idAfterHostChange), 'pve');
    });
  });

  group('matchNodeKey — çakışma (2+ eşleşme) → null', () {
    test('iki farklı sunucudan aynı node adı varsa belirsiz sayılır, null döner', () {
      // Asıl çakışma senaryosu: iki ayrı sunucu (host farklı) aynı node
      // adını ("pve") raporluyor — eski bir çıplak "pve" kaydı bu ikisinden
      // HANGİSİNE ait olduğu bilinemez, matchNodeKey rastgele birini
      // seçmek yerine null dönüp çağıranı varsayılana düşürmeli.
      final map = {
        composeNodeId('192.168.1.10', 'pve'): 'serviceA',
        composeNodeId('192.168.1.20', 'pve'): 'serviceB',
      };
      expect(matchNodeKey(map, 'pve'), isNull);
    });
  });

  group('matchNodeKey — hiç eşleşme yok → null', () {
    test('map\'te ne tam ne ada göre eşleşen bir anahtar yoksa null döner', () {
      final map = {composeNodeId('192.168.1.10', 'pve'): 1};
      expect(matchNodeKey(map, 'baska-node'), isNull);
    });

    test('boş map için de null döner', () {
      final map = <String, int>{};
      expect(matchNodeKey(map, 'pve'), isNull);
    });
  });
}
