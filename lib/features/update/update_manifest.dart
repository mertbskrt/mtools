class UpdateManifest {
  final String latestVersion;
  final int versionCode;
  final String minVersion;
  final String apkUrl;
  final String sha256;
  final String releaseNotes;
  final DateTime releaseDate;
  final bool mandatory;

  UpdateManifest({
    required this.latestVersion,
    required this.versionCode,
    required this.minVersion,
    required this.apkUrl,
    required this.sha256,
    required this.releaseNotes,
    required this.releaseDate,
    required this.mandatory,
  });

  factory UpdateManifest.fromJson(Map<String, dynamic> j) => UpdateManifest(
        latestVersion: j['latestVersion'] as String,
        versionCode: j['versionCode'] as int,
        minVersion: j['minVersion'] as String,
        apkUrl: j['apkUrl'] as String,
        sha256: (j['sha256'] as String).toLowerCase(),
        releaseNotes: j['releaseNotes'] as String? ?? '',
        releaseDate: DateTime.parse(j['releaseDate'] as String),
        mandatory: j['mandatory'] as bool? ?? false,
      );
}
