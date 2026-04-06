class GalleryImage {
  final String name;
  final String path;
  final String sha;
  final int size;
  final String downloadUrl;
  final int index;
  final double aspectRatio;

  const GalleryImage({
    required this.name,
    required this.path,
    required this.sha,
    required this.size,
    required this.downloadUrl,
    required this.index,
    required this.aspectRatio,
  });

  factory GalleryImage.fromGithubJson(Map<String, dynamic> json, {double? aspectRatio}) {
    final nameStr = json['name'].toString();
    final baseName = nameStr.replaceAll('.webp', '');
    final indexString = baseName.split('_').first;
    int index = int.tryParse(indexString) ?? 0;

    return GalleryImage(
      name: json['name'],
      path: json['path'],
      sha: json['sha'],
      size: json['size'],
      downloadUrl: json['download_url'],
      index: index,
      aspectRatio: aspectRatio ?? 1.0,
    );
  }

  GalleryImage copyWith({double? aspectRatio}) {
    return GalleryImage(
      name: name,
      path: path,
      sha: sha,
      size: size,
      downloadUrl: downloadUrl,
      index: index,
      aspectRatio: aspectRatio ?? this.aspectRatio,
    );
  }

  factory GalleryImage.fromJson(Map<String, dynamic> json) {
    return GalleryImage(
      name: json['name'],
      path: json['path'],
      sha: json['sha'],
      size: json['size'],
      downloadUrl: json['download_url'],
      index: json['index'],
      aspectRatio: (json['aspect_ratio'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'path': path,
      'sha': sha,
      'size': size,
      'download_url': downloadUrl,
      'index': index,
      'aspect_ratio': aspectRatio,
    };
  }
}
