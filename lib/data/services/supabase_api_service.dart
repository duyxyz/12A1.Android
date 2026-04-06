import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseApiService {
  final SupabaseClient _client;

  SupabaseApiService(this._client);

  Future<List<Map<String, dynamic>>> fetchImageMetadata() async {
    final data = await _client
        .from('images')
        .select()
        .order('image_index', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> upsertImageMetadata({
    required int index,
    required String name,
    required String sha,
    required int size,
    required int width,
    required int height,
  }) async {
    await _client.from('images').upsert({
      'image_index': index,
      'name': name,
      'sha': sha,
      'size': size,
      'width': width,
      'height': height,
      'aspect_ratio': width / height,
    });
  }

  Future<void> deleteImageMetadata(int index) async {
    await _client.from('images').delete().eq('image_index', index);
  }

  Future<void> bulkUpsertImageMetadata(List<Map<String, dynamic>> dataList) async {
    if (dataList.isEmpty) return;
    await _client.from('images').upsert(dataList);
  }

  Future<int> reserveNextImageIndex() async {
    final result = await _client.rpc('reserve_next_image_index');
    if (result is int) return result;
    if (result is num) return result.toInt();
    throw Exception('Invalid index returned from Supabase RPC.');
  }

  Stream<List<Map<String, dynamic>>> getMetadataStream() {
    return _client
        .from('images')
        .stream(primaryKey: ['image_index'])
        .order('image_index', ascending: false);
  }
}
