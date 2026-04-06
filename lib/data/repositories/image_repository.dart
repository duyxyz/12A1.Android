import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/gallery_image.dart';
import '../services/github_api_service.dart';
import '../services/supabase_api_service.dart';
import 'dart:typed_data';

class ImageRepository {
  static const String _cacheKey = 'local_image_metadata';
  final GithubApiService _githubApi;
  final SupabaseApiService _supabaseApi;

  ImageRepository(this._githubApi, this._supabaseApi);

  Future<List<GalleryImage>> getCachedImages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString(_cacheKey);
      if (cachedData == null) return [];

      final List<dynamic> decoded = jsonDecode(cachedData);
      return decoded.map((item) => GalleryImage.fromJson(item)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> _saveToCache(List<GalleryImage> images) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(images.map((img) => img.toJson()).toList());
      await prefs.setString(_cacheKey, encoded);
    } catch (_) {}
  }

  Future<List<GalleryImage>> getImages() async {
    // 1. Chỉ lấy metadata từ Supabase (Đã bao gồm tên file, sha, size)
    final metadataList = await _supabaseApi.fetchImageMetadata();

    // 2. Chuyển đổi trực tiếp sang GalleryImage mà không cần hỏi GitHub
    final images = metadataList.map((item) {
      final filename = item['name'] as String?;
      if (filename == null || filename.isEmpty) return null;
      
      final index = item['image_index'] as int;
      final aspectRatio = (item['aspect_ratio'] as num).toDouble();
      final sha = item['sha'] as String? ?? '';
      final size = item['size'] as int? ?? 0;

      return GalleryImage(
        name: filename,
        path: filename,
        sha: sha,
        size: size,
        // Tự xây dựng URL GitHub Raw dựa trên tên file
        downloadUrl: 'https://raw.githubusercontent.com/${_githubApi.owner}/${_githubApi.imageRepo}/refs/heads/main/$filename',
        index: index,
        aspectRatio: aspectRatio,
      );
    }).whereType<GalleryImage>().toList();

    images.sort((a, b) => b.index.compareTo(a.index));
    
    // Cập nhật bộ nhớ đệm
    _saveToCache(images);
    
    return images;
  }

  Future<void> uploadImage(String filename, Uint8List bytes, int width, int height) async {
    // 1. Dự trữ index trong Supabase
    final index = await _supabaseApi.reserveNextImageIndex();
    final indexedFilename = '${index}_$filename';

    // 2. Tải lên GitHub và lấy thông tin phản hồi (sha, size)
    final response = await _githubApi.uploadImage(indexedFilename, bytes);
    final content = response['content'] as Map<String, dynamic>;
    final sha = content['sha'] as String;
    final size = content['size'] as int;

    // 3. Lưu toàn bộ metadata vào Supabase
    await _supabaseApi.upsertImageMetadata(
      index: index,
      name: indexedFilename,
      sha: sha,
      size: size,
      width: width,
      height: height,
    );
  }

  Future<void> deleteImage(GalleryImage image) async {
    // 1. Delete from GitHub
    await _githubApi.deleteImage(image.path, image.sha);

    // 2. Delete metadata from Supabase
    await _supabaseApi.deleteImageMetadata(image.index);
  }

  Future<void> bulkUpsertMetadata(List<Map<String, dynamic>> data) async {
    await _supabaseApi.bulkUpsertImageMetadata(data);
  }

  Stream<Map<int, double>> watchMetadata() {
    return _supabaseApi.getMetadataStream().map((metadata) {
      return {
        for (final item in metadata)
          item['image_index'] as int: (item['aspect_ratio'] as num).toDouble(),
      };
    });
  }
}
