import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';

/// Alt menüdeki seçili ikon/etiket geçişinin süresi. Genel AppMotion.base
/// (250 ms) yerine biraz daha kısa — sekme değişimi anında hissettirsin.
const kBottomNavAnimation = Duration(milliseconds: 200);

/// Alt menüdeki tek sekme. Ana ekranın (home_screen.dart) alt çubuğu özel
/// bir Row; her hücre bu widget'la çizilir.
///
/// - Dokunma alanı hücrenin tamamı: [HitTestBehavior.opaque] + üst Row'daki
///   Expanded sayesinde ikonun etrafındaki boşluk da tepki verir.
/// - Sekme gerçekten değişince kısa bir seçim titreşimi
///   ([HapticFeedback.selectionClick]); seçili sekmeye tekrar dokunmak ya da
///   tanıtım turu sırasında dokunmak hiçbir şey yapmaz. Sistemdeki
///   "Dokunma geri bildirimi" ayarı kapalıysa Android titreştirmez.
class BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int currentIndex;
  final bool tourActive;
  final void Function(int) onTap;

  const BottomNavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.index,
    required this.currentIndex,
    required this.tourActive,
    required this.onTap,
  });

  void _handleTap() {
    if (tourActive || index == currentIndex) return;
    HapticFeedback.selectionClick();
    onTap(index);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final bool isSelected = index == currentIndex;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: kBottomNavAnimation,
                curve: AppMotion.curve,
                transform:
                    Matrix4.translationValues(0, isSelected ? -2 : 0, 0),
                child: Icon(
                  icon,
                  color: isSelected ? colors.primary : colors.textMuted,
                  size: isSelected ? 24 : 20,
                ),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: kBottomNavAnimation,
                curve: AppMotion.curve,
                style: TextStyle(
                  color: isSelected ? colors.primary : colors.textMuted,
                  fontSize: isSelected ? 9.5 : 8.5,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                child: Text(label, maxLines: 1, overflow: TextOverflow.fade),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
