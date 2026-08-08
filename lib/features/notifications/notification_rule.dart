import 'package:flutter/material.dart';

enum NotificationTrigger {
  cpuHigh,
  ramHigh,
  diskTemp,
  diskUsage,
  swapHigh,
  containerStopped,
  containerStarted,
  nodeOffline,
  nodeOnline,
  vmStopped,
  vmStarted,
  upsBatteryLow,
  upsOnBattery,
  upsLoadHigh,
  upsOffline,
  upsTempHigh,
  // Kayıtlı kurallar trigger.index ile eşleştiği için yeni değerler HER ZAMAN
  // sona eklenmeli — arada bir yere eklemek mevcut kullanıcıların kayıtlı
  // ayarlarının yanlış tetikleyiciyle eşleşmesine (bozulmasına) yol açar.
  upsOnline,
  // UPS'in kendisi YANIT VERİYOR ama "kapalı" raporluyor olması (upsOffline)
  // ile UPS'e/NUT servisine HİÇ ulaşılamaması (bağlantı hatası) bilinçli
  // olarak ayrı iki sinyal.
  upsUnreachable,
  // AdGuard için sunucu tamamen erişilemez olduğunda ayrı bir sinyal.
  adguardUnreachable,
}

class NotificationRule {
  final NotificationTrigger trigger;
  bool enabled;
  double threshold;
  int cooldownMinutes; // ← YENİ
  final String label;
  final String description;
  final IconData icon;
  final String category;

  NotificationRule({
    required this.trigger,
    required this.enabled,
    required this.threshold,
    this.cooldownMinutes = 10, // ← varsayılan 10 dakika
    required this.label,
    required this.description,
    required this.icon,
    required this.category,
  });

  NotificationRule copyWith({
    bool? enabled,
    double? threshold,
    int? cooldownMinutes,
  }) {
    return NotificationRule(
      trigger: trigger,
      enabled: enabled ?? this.enabled,
      threshold: threshold ?? this.threshold,
      cooldownMinutes: cooldownMinutes ?? this.cooldownMinutes,
      label: label,
      description: description,
      icon: icon,
      category: category,
    );
  }

  Map<String, dynamic> toJson() => {
        'trigger': trigger.index,
        'enabled': enabled,
        'threshold': threshold,
        'cooldownMinutes': cooldownMinutes,
      };

  factory NotificationRule.fromJson(
      Map<String, dynamic> json, NotificationRule defaults) {
    return NotificationRule(
      trigger: defaults.trigger,
      enabled: json['enabled'] ?? defaults.enabled,
      threshold: (json['threshold'] ?? defaults.threshold).toDouble(),
      cooldownMinutes: json['cooldownMinutes'] ?? defaults.cooldownMinutes,
      label: defaults.label,
      description: defaults.description,
      icon: defaults.icon,
      category: defaults.category,
    );
  }

  static List<NotificationRule> defaults() => [
        NotificationRule(
          trigger: NotificationTrigger.cpuHigh,
          enabled: true,
          threshold: 80,
          cooldownMinutes: 10,
          label: 'Yüksek CPU Kullanımı',
          description: 'Makine CPU kullanımı eşiği aştığında bildir',
          icon: Icons.memory,
          category: 'Sistem Kaynakları',
        ),
        NotificationRule(
          trigger: NotificationTrigger.ramHigh,
          enabled: true,
          threshold: 85,
          cooldownMinutes: 10,
          label: 'Yüksek RAM Kullanımı',
          description: 'Makine RAM kullanımı eşiği aştığında bildir',
          icon: Icons.storage,
          category: 'Sistem Kaynakları',
        ),
        NotificationRule(
          trigger: NotificationTrigger.swapHigh,
          enabled: false,
          threshold: 70,
          cooldownMinutes: 10,
          label: 'Yüksek Swap Kullanımı',
          description: 'Swap kullanımı eşiği aştığında bildir',
          icon: Icons.swap_horiz,
          category: 'Sistem Kaynakları',
        ),
        NotificationRule(
          trigger: NotificationTrigger.diskTemp,
          enabled: true,
          threshold: 55,
          cooldownMinutes: 10,
          label: 'Yüksek Disk Sıcaklığı',
          description: 'Disk sıcaklığı eşiği aştığında bildir',
          icon: Icons.thermostat,
          category: 'Sistem Kaynakları',
        ),
        NotificationRule(
          trigger: NotificationTrigger.diskUsage,
          enabled: true,
          threshold: 85,
          cooldownMinutes: 30,
          label: 'Yüksek Disk Kullanımı',
          description: 'Disk doluluk oranı eşiği aştığında bildir',
          icon: Icons.disc_full,
          category: 'Sistem Kaynakları',
        ),
        NotificationRule(
          trigger: NotificationTrigger.containerStopped,
          enabled: true,
          threshold: 0,
          cooldownMinutes: 0,
          label: 'Konteyner Durdu',
          description: 'Bir konteyner beklenmedik şekilde durduğunda bildir',
          icon: Icons.stop_circle_outlined,
          category: 'Konteyner',
        ),
        NotificationRule(
          trigger: NotificationTrigger.containerStarted,
          enabled: false,
          threshold: 0,
          cooldownMinutes: 0,
          label: 'Konteyner Başladı',
          description: 'Bir konteyner başladığında bildir',
          icon: Icons.play_circle_outlined,
          category: 'Konteyner',
        ),
        NotificationRule(
          trigger: NotificationTrigger.vmStopped,
          enabled: true,
          threshold: 0,
          cooldownMinutes: 0,
          label: 'Sanal Makine Durdu',
          description: 'Bir sanal makine durduğunda bildir',
          icon: Icons.computer,
          category: 'Sanal Makine',
        ),
        NotificationRule(
          trigger: NotificationTrigger.vmStarted,
          enabled: false,
          threshold: 0,
          cooldownMinutes: 0,
          label: 'Sanal Makine Başladı',
          description: 'Bir sanal makine başladığında bildir',
          icon: Icons.computer,
          category: 'Sanal Makine',
        ),
        NotificationRule(
          trigger: NotificationTrigger.nodeOffline,
          enabled: true,
          threshold: 0,
          cooldownMinutes: 0,
          label: 'Makine Çevrimdışı',
          description: 'Bir makine çevrimdışı olduğunda bildir',
          icon: Icons.cloud_off,
          category: 'Makine Durumu',
        ),
        NotificationRule(
          trigger: NotificationTrigger.nodeOnline,
          enabled: false,
          threshold: 0,
          cooldownMinutes: 0,
          label: 'Makine Çevrimiçi',
          description: 'Çevrimdışı makine tekrar çevrimiçi olduğunda bildir',
          icon: Icons.cloud_done,
          category: 'Makine Durumu',
        ),
        NotificationRule(
          trigger: NotificationTrigger.upsOnBattery,
          enabled: true,
          threshold: 0,
          cooldownMinutes: 5,
          label: 'UPS Bataryaya Geçti',
          description: 'Elektrik kesilince UPS batarya ile çalışmaya başladığında bildir',
          icon: Icons.battery_charging_full,
          category: 'UPS',
        ),
        NotificationRule(
          trigger: NotificationTrigger.upsOnline,
          enabled: true,
          threshold: 0,
          cooldownMinutes: 5,
          label: 'UPS Şebekeye Döndü',
          description: 'Elektrik gelince UPS tekrar şebeke gücüne geçtiğinde bildir',
          icon: Icons.bolt,
          category: 'UPS',
        ),
        NotificationRule(
          trigger: NotificationTrigger.upsBatteryLow,
          enabled: true,
          threshold: 30,
          cooldownMinutes: 5,
          label: 'UPS Düşük Batarya',
          description: 'UPS batarya seviyesi eşiğin altına düştüğünde bildir',
          icon: Icons.battery_alert,
          category: 'UPS',
        ),
        NotificationRule(
          trigger: NotificationTrigger.upsLoadHigh,
          enabled: false,
          threshold: 80,
          cooldownMinutes: 10,
          label: 'UPS Yüksek Yük',
          description: 'UPS yük oranı eşiği aştığında bildir',
          icon: Icons.electric_bolt,
          category: 'UPS',
        ),
        NotificationRule(
          trigger: NotificationTrigger.upsOffline,
          enabled: true,
          threshold: 0,
          cooldownMinutes: 0,
          label: 'UPS Kapatıldı',
          description:
              'NUT sunucusu yanıt veriyor ama UPS birimi kapalı raporluyorsa bildir',
          icon: Icons.power_off,
          category: 'UPS',
        ),
        NotificationRule(
          trigger: NotificationTrigger.upsUnreachable,
          enabled: true,
          threshold: 0,
          cooldownMinutes: 5,
          label: 'UPS\'e Ulaşılamıyor',
          description:
              'UPS sunucusuna (NUT) hiç bağlanılamadığında bildir — güç kesintisinde UPS\'in kendisi kapandığında bu duruma düşer',
          icon: Icons.wifi_off_rounded,
          category: 'UPS',
        ),
        NotificationRule(
          trigger: NotificationTrigger.upsTempHigh,
          enabled: false,
          threshold: 40,
          cooldownMinutes: 10,
          label: 'UPS Yüksek Sıcaklık',
          description: 'UPS sıcaklığı eşiği aştığında bildir',
          icon: Icons.thermostat,
          category: 'UPS',
        ),
        NotificationRule(
          trigger: NotificationTrigger.adguardUnreachable,
          enabled: true,
          threshold: 0,
          cooldownMinutes: 5,
          label: 'AdGuard\'a Ulaşılamıyor',
          description:
              'AdGuard Home sunucusuna hiç bağlanılamadığında bildir',
          icon: Icons.wifi_off_rounded,
          category: 'AdGuard',
        ),
      ];
}
