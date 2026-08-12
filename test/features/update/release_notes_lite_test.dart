import 'package:flutter_test/flutter_test.dart';
import 'package:mtools/features/update/release_notes_lite.dart';

void main() {
  group('parseReleaseNotesLite', () {
    test('gerçek 3.2.1 notları — hiç # ya da - işareti yok, hepsi paragraf olmalı', () {
      const body =
          "Yeni: Wake-on-LAN Widget'ı\n"
          "Kayıtlı cihazlarınızı artık ana ekrandan, uygulamayı açmadan tek dokunuşla uyandırabilirsiniz.\n"
          "\n"
          "Yeni: Proxmox Widget'ında Sunucu Seçimi\n"
          "Widget'ı artık sadece istediğiniz sunucuları gösterecek şekilde özelleştirebilir, farklı seçimlerle birden fazla widget ekleyebilirsiniz.\n"
          "\n"
          "İyileştirme: Daha Akıllı Bağlantı Bildirimleri\n"
          "Telefonunuzun interneti kesildiğinde artık tek, net bir bildirim alıyorsunuz — cihazınızın bağlantı sorunu ile sunucuya ulaşılamaması artık birbirinden ayrılıyor.\n"
          "\n"
          "İyileştirme: Widget Tutarlılığı\n"
          "Dört ana ekran widget'ı (Proxmox, UPS, AdGuard, Wake-on-LAN) artık boyut, renk ve mesajlarda daha tutarlı; Wake-on-LAN'ın \"hepsini uyandır\" butonu art arda dokunuşlarda artık tekrar paket göndermiyor.";

      final lines = parseReleaseNotesLite(body);

      // Boş satırlar atlanmış olmalı (4 başlık-benzeri + 4 açıklama = 8 satır)
      expect(lines, hasLength(8));
      // Hiçbir satır yanlışlıkla heading/bullet olarak sınıflandırılmamalı —
      // metinde ne '#' ne de '-'/'*'/'•' ile başlayan bir satır var.
      expect(lines.every((l) => l.type == ReleaseNoteLineType.paragraph), isTrue);
      expect(lines.first.text, "Yeni: Wake-on-LAN Widget'ı");
      expect(lines.last.text, contains('Wake-on-LAN'));
    });

    test('markdown başlık + madde işaretli bir gövde doğru sınıflandırılır', () {
      const body = '## Özellikler\n'
          '- İlk madde\n'
          '* İkinci madde (yıldızla)\n'
          '\n'
          'Düz bir paragraf satırı.';

      final lines = parseReleaseNotesLite(body);

      expect(lines, hasLength(4));
      expect(lines[0].type, ReleaseNoteLineType.heading);
      expect(lines[0].text, 'Özellikler');
      expect(lines[1].type, ReleaseNoteLineType.bullet);
      expect(lines[1].text, 'İlk madde');
      expect(lines[2].type, ReleaseNoteLineType.bullet);
      expect(lines[2].text, 'İkinci madde (yıldızla)');
      expect(lines[3].type, ReleaseNoteLineType.paragraph);
      expect(lines[3].text, 'Düz bir paragraf satırı.');
    });

    test('boş gövde boş liste döner', () {
      expect(parseReleaseNotesLite(''), isEmpty);
      expect(parseReleaseNotesLite('   \n\n  '), isEmpty);
    });
  });
}
