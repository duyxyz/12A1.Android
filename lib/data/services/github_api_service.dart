import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'dart:typed_data';

class GithubApiService {
  final String token;
  final String owner;
  final String imageRepo;
  final String appRepo;
  final Function(String)? onRateLimitUpdate;

  GithubApiService({
    required this.token,
    required this.owner,
    required this.imageRepo,
    required this.appRepo,
    this.onRateLimitUpdate,
  });

  String get _imagesBaseUrl => 'https://api.github.com/repos/$owner/$imageRepo/contents';
  String get _releasesUrl => 'https://api.github.com/repos/$owner/$appRepo/releases/latest';

  Map<String, String> get _headers {
    final result = <String, String>{
      'Accept': 'application/vnd.github.v3+json',
    };
    if (token.isNotEmpty) {
      result['Authorization'] = 'token $token';
    }
    return result;
  }

  void _updateRateLimit(http.BaseResponse response) {
    if (onRateLimitUpdate != null && response.headers.containsKey('x-ratelimit-remaining')) {
      onRateLimitUpdate!(response.headers['x-ratelimit-remaining'] ?? 'Unknown');
    }
  }

  Future<List<Map<String, dynamic>>> fetchRawImages() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final url = '$_imagesBaseUrl?t=$timestamp';
    
    final response = await http
        .get(Uri.parse(url), headers: _headers)
        .timeout(const Duration(seconds: 20));

    _updateRateLimit(response);

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('GitHub API Error (${response.statusCode}): ${response.body}');
    }
  }

  Future<Map<String, dynamic>> uploadImage(String filename, Uint8List fileBytes) async {
    final base64Image = base64Encode(fileBytes);
    final response = await http
        .put(
          Uri.parse('$_imagesBaseUrl/$filename'),
          headers: _headers,
          body: jsonEncode({
            'message': 'Upload $filename (Android App)',
            'content': base64Image,
          }),
        )
        .timeout(const Duration(seconds: 30));

    _updateRateLimit(response);

    if (response.statusCode == 201 || response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to upload image: ${response.body}');
    }
  }

  Future<void> deleteImage(String path, String sha) async {
    final response = await http
        .delete(
          Uri.parse('$_imagesBaseUrl/$path'),
          headers: _headers,
          body: jsonEncode({'message': 'Delete $path (Android App)', 'sha': sha}),
        )
        .timeout(const Duration(seconds: 30));

    _updateRateLimit(response);

    if (response.statusCode != 200) {
      throw Exception('Failed to delete image: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> fetchLatestRelease() async {
    final response = await http
        .get(Uri.parse(_releasesUrl), headers: _headers)
        .timeout(const Duration(seconds: 20));

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to fetch update info: ${response.statusCode}');
    }
  }

  Future<void> downloadFile({
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
