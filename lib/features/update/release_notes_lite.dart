/// GitHub release'lerinin `body` alanı markdown formatında gelir ama tam bir
/// markdown kütüphanesi gerektirmeyecek kadar sade — çoğu zaman (ör. mevcut
/// 3.2.1 notları) hiç `#`/`-` işareti bile taşımıyor, düz paragraf metni.
/// Bu satır satır çalışan basit ayrıştırıcı üç durumu ayırt eder: başlık
/// (`#`..`######`), madde işareti (`-`/`*`/`•`) ve düz paragraf — hiçbiri
/// eşleşmezse (ki bugünkü release notlarının tamamı bu durumda) satır
/// olduğu gibi paragraf olarak render edilir.
enum ReleaseNoteLineType { heading, bullet, paragraph }

class ReleaseNoteLine {
  final ReleaseNoteLineType type;
  final String text;
  const ReleaseNoteLine(this.type, this.text);
}

final _headingPattern = RegExp(r'^#{1,6}\s+(.*)$');
final _bulletPattern = RegExp(r'^[-*•]\s+(.*)$');

List<ReleaseNoteLine> parseReleaseNotesLite(String body) {
  final result = <ReleaseNoteLine>[];
  for (final raw in body.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;

    final heading = _headingPattern.firstMatch(line);
    if (heading != null) {
      result.add(ReleaseNoteLine(ReleaseNoteLineType.heading, heading.group(1)!.trim()));
      continue;
    }

    final bullet = _bulletPattern.firstMatch(line);
    if (bullet != null) {
      result.add(ReleaseNoteLine(ReleaseNoteLineType.bullet, bullet.group(1)!.trim()));
      continue;
    }

    result.add(ReleaseNoteLine(ReleaseNoteLineType.paragraph, line));
  }
  return result;
}
