import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'supabase_service.dart';

class GithubService {
  static String get token {
    const tokenFromEnv = String.fromEnvironment('GH_TOKEN');
    return tokenFromEnv.isNotEmpty ? tokenFromEnv : '';
  }

  static const String owner = 'duyxyz';
  static const String imageRepo = '12A1.Galary';
  static const String appRepo = '12A1.Android';
  static const String baseUrl =
      'https://api.github.com/repos/$owner/$imageRepo/contents';

  static final ValueNotifier<String> apiRemaining = ValueNotifier<String>(
    'Đang kiểm tra...',
  );

  static Map<String, String> get headers {
    final result = <String, String>{
      'Accept': 'application/vnd.github.v3+json',
    };
    if (token.isNotEmpty) {
      result['Authorization'] = 'token $token';
    }
    return result;
  }

  static void _updateRateLimit(http.Response response) {
    if (response.headers.containsKey('x-ratelimit-remaining')) {
      apiRemaining.value =
          response.headers['x-ratelimit-remaining'] ?? 'Unknown';
    }
  }

  static Future<List<Map<String, dynamic>>> fetchImages() async {
    Map<int, double> aspectRatios = {};

    // 1. Get metadata from Supabase
    try {
      final metadata = await SupabaseService.fetchImageMetadata();
      for (var item in metadata) {
        final idx = item['image_index'];
        final ratio = item['aspect_ratio'];
        if (idx != null && ratio != null) {
          aspectRatios[idx as int] = (ratio as num).toDouble();
        }
      }
    } catch (_) {}

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final url = '$baseUrl?t=$timestamp';
    final response = await http
        .get(Uri.parse(url), headers: headers)
        .timeout(const Duration(seconds: 20));
    _updateRateLimit(response);

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      List<Map<String, dynamic>> images = [];
      for (var file in data) {
        if (file['name'].toString().endsWith('.webp')) {
          final nameStr = file['name'].toString();
          final baseName = nameStr.replaceAll('.webp', '');
          final indexString = baseName.split('_').first;
          int index = int.tryParse(indexString) ?? 0;
          images.add({
            'name': file['name'],
            'path': file['path'],
            'sha': file['sha'],
            'size': file['size'],
            'download_url': file['download_url'],
            'index': index,
            'aspect_ratio': (aspectRatios[index] ?? 1.0).toDouble(),
          });
        }
      }
      images.sort((a, b) => b['index'].compareTo(a['index']));
      return images;
    } else {
      throw Exception('Lỗi API (${response.statusCode}): ${response.body}');
    }
  }

  static Future<void> uploadImage(String filename, Uint8List fileBytes) async {
    final base64Image = base64Encode(fileBytes);
    final response = await http
        .put(
          Uri.parse('$baseUrl/$filename'),
          headers: headers,
          body: jsonEncode({
            'message': 'Upload $filename (Android App)',
            'content': base64Image,
          }),
        )
        .timeout(const Duration(seconds: 30));
    _updateRateLimit(response);

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Failed to upload image: ${response.body}');
    }
  }

  static Future<void> deleteImage(String path, String sha) async {
    final response = await http
        .delete(
          Uri.parse('$baseUrl/$path'),
          headers: headers,
          body: jsonEncode({'message': 'Delete $path (Android App)', 'sha': sha}),
        )
        .timeout(const Duration(seconds: 30));
    _updateRateLimit(response);

    if (response.statusCode != 200) {
      throw Exception('Failed to delete image: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>?> findBestAsset(
    List<dynamic> assets,
  ) async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    final supportedAbis = androidInfo.supportedAbis;

    for (var abi in supportedAbis) {
      for (var asset in assets) {
        final name = asset['name'].toString().toLowerCase();
        if (name.contains(abi.toLowerCase()) && name.endsWith('.apk')) {
          return asset as Map<String, dynamic>;
        }
      }
    }

    for (var asset in assets) {
      if (asset['name'].toString().endsWith('.apk')) {
        return asset as Map<String, dynamic>;
      }
    }
    return null;
  }

  static Future<Map<String, dynamic>> checkUpdate() async {
    try {
      final response = await http
          .get(
            Uri.parse(
              'https://api.github.com/repos/$owner/$appRepo/releases/latest',
            ),
            headers: headers,
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        return {'success': true, 'data': json.decode(response.body)};
      } else {
        return {
          'success': false,
          'error': 'Lỗi ${response.statusCode}: ${response.reasonPhrase}',
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  static Future<void> downloadFile({
    required String url,
    required String savePath,
    required Function(double) onProgress,
  }) async {
    final dio = Dio();
    await dio.download(
      url,
      savePath,
      onReceiveProgress: (received, total) {
        if (total != -1) {
          onProgress(received / total);
        }
      },
    );
  }
}
