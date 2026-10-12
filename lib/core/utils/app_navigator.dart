import 'package:flutter/widgets.dart';

/// MaterialApp'in kök Navigator'ı. Kendi BuildContext'inden Navigator'a
/// ulaşamayabilen yerler (ör. ErrorWidget.builder'ın çizdiği hata ekranı —
/// hata Navigator'ın üstünde bir widget'ta da olabilir) bunun üzerinden
/// sayfa açar.
final appNavigatorKey = GlobalKey<NavigatorState>();
