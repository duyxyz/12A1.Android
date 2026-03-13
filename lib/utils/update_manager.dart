import 'dart:io';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:open_filex/open_filex.dart';
import '../services/github_service.dart';

Future<void> startUpdateProcess(BuildContext context, Map<String, dynamic> updateData) async {
  if (!context.mounted) return;

  try {
    debugPrint("Bắt đầu quy trình cập nhật...");
    final assets = updateData['assets'] as List<dynamic>;
    final bestAsset = await GithubService.findBestAsset(assets);

    if (bestAsset == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không tìm thấy bản APK phù hợp cho thiết bị này!')),
        );
      }
      return;
    }

    final downloadUrl = bestAsset['browser_download_url'] as String;
    final fileName = bestAsset['name'] as String;

    debugPrint("Đã tìm thấy asset: $fileName");

    if (!context.mounted) return;
    
    final progressNotifier = ValueNotifier<double>(0);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Đang tải bản cập nhật...'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(fileName, style: const TextStyle(fontSize: 11, color: Colors.grey), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ValueListenableBuilder<double>(
                valueListenable: progressNotifier,
                builder: (context, value, _) {
                  return Column(
                    children: [
                      LinearProgressIndicator(value: value),
                      const SizedBox(height: 8),
                      Text('${(value * 100).toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );

    final tempDir = await getTemporaryDirectory();
    final savePath = p.join(tempDir.path, fileName);

    final oldFile = File(savePath);
    if (await oldFile.exists()) {
      await oldFile.delete();
    }

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 5),
    ));

    await dio.download(
      downloadUrl,
      savePath,
      onReceiveProgress: (received, total) {
        if (total != -1) {
          progressNotifier.value = received / total;
        }
      },
    );

    debugPrint("Tải xong: $savePath");

    if (context.mounted) {
       Navigator.of(context, rootNavigator: true).pop();
    }

    final result = await OpenFilex.open(savePath);
    if (result.type != ResultType.done) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi mở APK: ${result.message}')),
        );
      }
    }
  } catch (e) {
    debugPrint("Lỗi cập nhật: $e");
    if (context.mounted) {
      if (Navigator.canPop(context)) Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi: $e')),
      );
    }
  }
}

/// Xoá bỏ các file APK thừa trong bộ nhớ tạm để tiết kiệm dung lượng
Future<void> cleanupUpdateFiles() async {
  try {
    final tempDir = await getTemporaryDirectory();
    if (!tempDir.existsSync()) return;

    final List<FileSystemEntity> files = tempDir.listSync();
    for (final file in files) {
      if (file is File && file.path.endsWith('.apk')) {
        try {
          await file.delete();
          debugPrint("Đã xoá file update cũ: ${file.path}");
        } catch (e) {
          debugPrint("Không thể xoá file ${file.path}: $e");
        }
      }
    }
  } catch (e) {
    debugPrint("Lỗi khi dọn dẹp file update: $e");
  }
}
