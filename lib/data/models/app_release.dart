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
    // Loại bỏ tiền tố 'v' và các khoảng trắng
    String cleaned = tagName.toLowerCase().replaceFirst('v', '').trim();
    
    // Chuẩn hóa: Biến "2024.04.09" thành "2024.4.9" để khớp với PackageInfo của Flutter
    try {
      return cleaned.split('.').map((part) {
        final parsed = int.tryParse(part);
        return parsed != null ? parsed.toString() : part;
      }).join('.');
    } catch (_) {
      return cleaned;
    }
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
