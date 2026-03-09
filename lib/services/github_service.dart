import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

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

  static Map<String, String> get headers => {
    'Authorization': 'token $token',
    'Accept': 'application/vnd.github.v3+json',
  };

  static void _updateRateLimit(http.Response response) {
    if (response.headers.containsKey('x-ratelimit-remaining')) {
      apiRemaining.value =
          response.headers['x-ratelimit-remaining'] ?? 'Unknown';
    }
  }

  static Future<List<Map<String, dynamic>>> fetchImages() async {
    Map<int, double> aspectRatios = {};
    try {
      final jsonResponse = await http.get(
        Uri.parse(
          'https://raw.githubusercontent.com/duyxyz/12A1.Galary/main/images.json',
        ),
      );
      if (jsonResponse.statusCode == 200) {
        final List<dynamic> jsonData = json.decode(jsonResponse.body);
        for (var item in jsonData) {
          if (item is Map &&
              item['i'] != null &&
              item['w'] != null &&
              item['h'] != null) {
            aspectRatios[item['i']] = item['w'] / item['h'];
          }
        }
      }
    } catch (_) {}

    final response = await http.get(Uri.parse(baseUrl), headers: headers);
    _updateRateLimit(response);

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      List<Map<String, dynamic>> images = [];
      for (var file in data) {
        if (file['name'].toString().endsWith('.webp')) {
          int index =
              int.tryParse(file['name'].toString().replaceAll('.webp', '')) ??
              0;
          images.add({
            'name': file['name'],
            'path': file['path'],
            'sha': file['sha'],
            'download_url': file['download_url'],
            'index': index,
            'aspect_ratio': aspectRatios[index] ?? 1.0,
          });
        }
      }
      images.sort(
        (a, b) => b['index'].compareTo(a['index']),
      );
      return images;
    } else {
      throw Exception('Lỗi API (${response.statusCode}): ${response.body}');
    }
  }

  static Future<void> uploadImage(String filename, Uint8List fileBytes) async {
    final base64Image = base64Encode(fileBytes);
    final response = await http.put(
      Uri.parse('$baseUrl/$filename'),
      headers: headers,
      body: jsonEncode({
        'message': 'Upload $filename (Android App)',
        'content': base64Image,
      }),
    );
    _updateRateLimit(response);

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Failed to upload image: ${response.body}');
    }
  }

  static Future<void> deleteImage(String path, String sha) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/$path'),
      headers: headers,
      body: jsonEncode({'message': 'Delete $path (Android App)', 'sha': sha}),
    );
    _updateRateLimit(response);

    if (response.statusCode != 200) {
      throw Exception('Failed to delete image: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>?> findBestAsset(List<dynamic> assets) async {
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
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$owner/$appRepo/releases/latest'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        return {
          'success': true,
          'data': json.decode(response.body),
        };
      } else {
        return {
          'success': false,
          'error': 'Lỗi ${response.statusCode}: ${response.reasonPhrase}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Lỗi kết nối: $e',
      };
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
