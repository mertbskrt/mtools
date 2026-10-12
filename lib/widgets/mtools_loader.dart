import 'dart:math' as math;

import 'package:flutter/material.dart';

/// MTools yükleme göstergesi.
///
/// Ortada sabit MTools işareti, etrafında dönen yeşil bir yay ve hafifçe
/// nabız atan yeşil nokta. 24 pikselden küçük boyutlarda logo okunmadığı için
/// sadece dönen yay çizilir (buton içi, satır içi kullanım).
///
/// Kullanım:
///   const MToolsLoader()                       // 48 px, tam ekran / kart içi
///   const MToolsLoader(size: 96, label: 'Yükleniyor')
///   const MToolsLoader(size: 18)               // buton içi küçük varyant
class MToolsLoader extends StatefulWidget {
  const MToolsLoader({super.key, this.size = 48, this.label});

  /// Göstergenin genişliği ve yüksekliği.
  final double size;

  /// Altta gösterilecek isteğe bağlı metin.
  final String? label;

  @override
  State<MToolsLoader> createState() => _MToolsLoaderState();
}

class _MToolsLoaderState extends State<MToolsLoader>
    with TickerProviderStateMixin {
  static const _yesil = Color(0xFF22B573);

  late final AnimationController _donus = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final AnimationController _nabiz = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  bool _hareketKapali = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // "Animasyonları kaldır" erişilebilirlik ayarı açıksa animasyon çalışmaz.
    _hareketKapali = MediaQuery.of(context).disableAnimations;
    if (_hareketKapali) {
      _donus.stop();
      _nabiz.stop();
    } else {
      if (!_donus.isAnimating) _donus.repeat();
      if (!_nabiz.isAnimating) _nabiz.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _donus.dispose();
    _nabiz.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final koyu = Theme.of(context).brightness == Brightness.dark;
    final isaretRengi = koyu ? Colors.white : const Color(0xFF1B1C1F);

    final gosterge = RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(
          painter: _MToolsLoaderPainter(
            donus: _donus,
            nabiz: _nabiz,
            hareketKapali: _hareketKapali,
            isaretRengi: isaretRengi,
            yesil: _yesil,
          ),
        ),
      ),
    );

    final label = widget.label;
    final icerik = label == null
        ? gosterge
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              gosterge,
              SizedBox(height: widget.size * 0.28),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).hintColor,
                      letterSpacing: 0.3,
                    ),
              ),
            ],
          );

    return Semantics(
      label: label ?? 'Yükleniyor',
      liveRegion: true,
      child: icerik,
    );
  }
}

class _MToolsLoaderPainter extends CustomPainter {
  _MToolsLoaderPainter({
    required this.donus,
    required this.nabiz,
    required this.hareketKapali,
    required this.isaretRengi,
    required this.yesil,
  }) : super(repaint: Listenable.merge([donus, nabiz]));

  final Animation<double> donus;
  final Animation<double> nabiz;
  final bool hareketKapali;
  final Color isaretRengi;
  final Color yesil;

  // Logo geometrisi, 1024x1024 viewBox üzerinde.
  static const List<Offset> _mNoktalari = [
    Offset(205, 740),
    Offset(205, 362),
    Offset(402, 622),
    Offset(512, 284),
    Offset(622, 622),
    Offset(740, 386),
  ];
  static const Offset _nokta = Offset(811, 291);
  static const double _noktaYaricap = 51;
  static const double _cizgiKalinligi = 66;
  // Çizgi kalınlığı ve nokta dahil logonun sınırları: x 172..862, y 240..773
  static const Offset _logoMerkez = Offset(517, 506.5);
  static const double _logoGenislik = 690;

  @override
  void paint(Canvas canvas, Size size) {
    final boyut = size.shortestSide;
    final kucuk = boyut < 24;
    final halkaKalinligi = boyut * (kucuk ? 0.12 : 0.06);
    final merkez = size.center(Offset.zero);
    final yaricap = boyut / 2 - halkaKalinligi / 2;
    final halkaKutusu = Rect.fromCircle(center: merkez, radius: yaricap);

    // Soluk tam halka
    canvas.drawCircle(
      merkez,
      yaricap,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = halkaKalinligi
        ..color = yesil.withValues(alpha: 0.12),
    );

    // Dönen yay (hareket kapalıysa tam halka)
    final yay = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = halkaKalinligi
      ..strokeCap = StrokeCap.round
      ..color = yesil;
    if (hareketKapali) {
      canvas.drawCircle(merkez, yaricap, yay..strokeCap = StrokeCap.butt);
    } else {
      final baslangic = -math.pi / 2 + donus.value * 2 * math.pi;
      canvas.drawArc(halkaKutusu, baslangic, math.pi / 2, false, yay);
    }

    if (kucuk) return;

    // Logo, halkanın iç kısmına sığacak şekilde ölçeklenir.
    final olcek = (boyut * 0.56) / _logoGenislik;
    canvas.save();
    canvas.translate(merkez.dx, merkez.dy);
    canvas.scale(olcek);
    canvas.translate(-_logoMerkez.dx, -_logoMerkez.dy);

    final yol = Path()..moveTo(_mNoktalari.first.dx, _mNoktalari.first.dy);
    for (final n in _mNoktalari.skip(1)) {
      yol.lineTo(n.dx, n.dy);
    }
    canvas.drawPath(
      yol,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _cizgiKalinligi
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = isaretRengi,
    );

    // Nabız atan nokta: ölçek 1,0 ile 1,25 arası
    final t = hareketKapali ? 0.0 : Curves.easeInOut.transform(nabiz.value);
    canvas.drawCircle(
      _nokta,
      _noktaYaricap * (1 + 0.25 * t),
      Paint()..color = yesil,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MToolsLoaderPainter old) =>
      old.hareketKapali != hareketKapali ||
      old.isaretRengi != isaretRengi ||
      old.yesil != yesil;
}
