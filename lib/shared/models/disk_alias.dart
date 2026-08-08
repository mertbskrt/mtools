class DiskAlias {
  final String devpath;
  final String alias;
  final String icon;

  DiskAlias({
    required this.devpath,
    required this.alias,
    required this.icon,
  });

  Map<String, dynamic> toJson() => {
        'devpath': devpath,
        'alias': alias,
        'icon': icon,
      };

  factory DiskAlias.fromJson(Map<String, dynamic> json) => DiskAlias(
        devpath: json['devpath'] as String? ?? '',
        alias: json['alias'] as String? ?? '',
        icon: json['icon'] as String? ?? 'storage',
      );
}
