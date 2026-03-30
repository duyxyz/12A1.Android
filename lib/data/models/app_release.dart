class AppRelease {
  final String tagName;
  final String name;
  final String body;
  final DateTime publishedAt;
  final List<AppAsset> assets;

  AppRelease({
    required this.tagName,
    required this.name,
    required this.body,
    required this.publishedAt,
    required this.assets,
  });

  factory AppRelease.fromJson(Map<String, dynamic> json) {
    return AppRelease(
      tagName: json['tag_name'] ?? '',
      name: json['name'] ?? '',
      body: json['body'] ?? '',
      publishedAt: DateTime.parse(json['published_at']),
      assets: (json['assets'] as List? ?? [])
          .map((asset) => AppAsset.fromJson(asset))
          .toList(),
    );
  }

  String get version {
    final clean = tagName.replaceAll('v', '');
    if (clean.contains('+')) {
      return clean.split('+').first;
    }
    return clean;
  }

  int get buildNumber {
    final clean = tagName.replaceAll('v', '');
    if (clean.contains('+')) {
      return int.tryParse(clean.split('+').last) ?? 0;
    }
    return 0;
  }
}

class AppAsset {
  final String name;
  final int size;
  final String downloadUrl;
  final String contentType;

  AppAsset({
    required this.name,
    required this.size,
    required this.downloadUrl,
    required this.contentType,
  });

  factory AppAsset.fromJson(Map<String, dynamic> json) {
    return AppAsset(
      name: json['name'] ?? '',
      size: json['size'] ?? 0,
      downloadUrl: json['browser_download_url'] ?? '',
      contentType: json['content_type'] ?? '',
    );
  }
}
