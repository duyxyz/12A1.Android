import 'dart:convert';
import 'package:http/http.dart' as http;
import '../main.dart';

class MigrationUtility {
  static Future<String> migrateFromGitHub() async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://raw.githubusercontent.com/duyxyz/GG.G/main/images.json',
        ),
      );

      if (response.statusCode != 200) {
        return 'Lỗi fetch images.json: ${response.statusCode}';
      }

      final List<dynamic> jsonData = json.decode(response.body);
      List<Map<String, dynamic>> toUpsert = [];

      for (var item in jsonData) {
        if (item is Map) {
          final id = num.tryParse(item['i']?.toString() ?? '')?.toInt();
          final name = item['n']?.toString();
          final sha = item['sha']?.toString();
          final size = num.tryParse(item['s']?.toString() ?? '')?.toInt();
          final w = num.tryParse(item['w']?.toString() ?? '')?.toInt();
          final h = num.tryParse(item['h']?.toString() ?? '')?.toInt();

          if (id != null && w != null && h != null && h != 0) {
            toUpsert.add({
              'image_index': id,
              'name': name,
              'sha': sha,
              'size': size,
              'width': w,
              'height': h,
              'aspect_ratio': (w / h).toDouble(),
            });
          }
        }
      }

      if (toUpsert.isEmpty) {
        return 'Không tìm thấy dữ liệu hợp lệ trong images.json';
      }

      try {
        await AppDependencies.instance.imageRepository.bulkUpsertMetadata(
          toUpsert,
        );
        return 'Thành công đồng bộ ${toUpsert.length} ảnh sang Supabase!';
      } catch (dbError) {
        return 'Lỗi lưu vào Supabase: $dbError';
      }
    } catch (e) {
      return 'Lỗi hệ thống: $e';
    }
  }
}
