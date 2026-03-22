import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import '../services/github_service.dart';
import '../services/supabase_service.dart';
import '../utils/haptics.dart';
import '../widgets/error_view.dart';
import '../widgets/pulse_skeleton.dart';

class AddTab extends StatefulWidget {
  final List<Map<String, dynamic>> images;
  final bool isLoading;
  final String error;
  final Future<void> Function() onRefresh;

  const AddTab({
    super.key,
    required this.images,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
  });

  @override
  State<AddTab> createState() => _AddTabState();
}

class _AddTabState extends State<AddTab> {
  bool _isUploading = false;
  String _uploadStatus = "";
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _selectedImages = [];

  Future<void> _pickImage() async {
    AppHaptics.lightImpact();
    try {
      final List<XFile> images = await _picker.pickMultiImage();
      if (images.isNotEmpty) {
        setState(() {
          _selectedImages.addAll(images);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi chọn ảnh: $e')));
      }
    }
  }

  Future<void> _uploadImage() async {
    AppHaptics.lightImpact();
    if (_selectedImages.isEmpty) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Xác nhận Đăng Ảnh'),
          content: Text(
            'Bạn có chắc chắn muốn đăng ${_selectedImages.length} bức ảnh này lên Bộ Sưu Tập chung không?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Đồng ý'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() {
      _isUploading = true;
      _uploadStatus = "Bắt đầu tải lên...";
    });

    try {
      List<Map<String, dynamic>> currentImages = List.from(widget.images);

      for (int i = 0; i < _selectedImages.length; i++) {
        final image = _selectedImages[i];
        setState(() {
          _uploadStatus = "Đang xử lý ${i + 1}/${_selectedImages.length}...";
        });

        final Uint8List? compressedBytes =
            await FlutterImageCompress.compressWithFile(
              image.path,
              minWidth: 1920,
              minHeight: 1920,
              quality: 80,
              format: CompressFormat.webp,
            );

        if (compressedBytes == null) continue;

        int nextIndex = 1;
        List<int> existingIndexes =
            currentImages.map<int>((img) => img['index'] as int).toList()
              ..sort();

        for (int idx = 0; idx < existingIndexes.length; idx++) {
          if (existingIndexes[idx] == nextIndex) {
            nextIndex++;
          } else if (existingIndexes[idx] > nextIndex) {
            break;
          }
        }

        final filename = '$nextIndex.webp';
        await GithubService.uploadImage(filename, compressedBytes);

        // Calculate metadata and store in Supabase
        try {
          final decodedImage = img.decodeImage(compressedBytes);
          if (decodedImage != null) {
            await SupabaseService.upsertImageMetadata(
              nextIndex,
              decodedImage.width,
              decodedImage.height,
            );
          }
        } catch (e) {
          debugPrint('Lỗi lưu Supabase: $e');
        }

        currentImages.add({'index': nextIndex});
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã tải tất cả ảnh lên thành công!')),
        );
        setState(() {
          _selectedImages.clear();
        });
      }
      await widget.onRefresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi tải lên: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _removeImage(int index) {
    AppHaptics.lightImpact();
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  void _clearSelection() {
    AppHaptics.mediumImpact();
    setState(() {
      _selectedImages.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.error.isNotEmpty) {
      return ErrorView(
        message: 'Lỗi nạp dữ liệu: ${widget.error}',
        onRetry: widget.onRefresh,
        isFullScreen: false,
      );
    }

    return Scaffold(
      appBar: _selectedImages.isNotEmpty && !_isUploading
          ? AppBar(
              title: Text(
                'Đã chọn ${_selectedImages.length} ảnh',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              centerTitle: true,
              actions: [
                IconButton(
                  onPressed: _clearSelection,
                  icon: const Icon(Icons.delete_sweep_rounded),
                  tooltip: 'Xóa hết',
                ),
                const SizedBox(width: 8),
              ],
            )
          : null,
      body: Stack(
        children: [
          _selectedImages.isNotEmpty
          ? SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: GridView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                      itemCount: _selectedImages.length + 1,
                      itemBuilder: (context, index) {
                        if (index == _selectedImages.length) {
                          return InkWell(
                            onTap: _pickImage,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer
                                    .withValues(alpha: 0.3),
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.3),
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                Icons.add_rounded,
                                size: 32,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          );
                        }
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Theme.of(
                                      context,
                                    ).dividerColor.withValues(alpha: 0.1),
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.file(
                                    File(_selectedImages[index].path),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: GestureDetector(
                                onTap: () => _removeImage(index),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      border: Border(
                        top: BorderSide(
                          color: Theme.of(
                            context,
                          ).dividerColor.withValues(alpha: 0.2),
                          width: 1.0,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(
                            context,
                          ).shadowColor.withValues(alpha: 0.05),
                          offset: const Offset(0, -4),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: _uploadImage,
                        label: const Text(
                          'Đăng lên Bộ Sưu Tập',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: InkWell(
                        onTap: _pickImage,
                        borderRadius: BorderRadius.circular(32),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            vertical: 48,
                            horizontal: 24,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(32),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.5),
                              width: 2,
                              strokeAlign: BorderSide.strokeAlignInside,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.add_photo_alternate_rounded,
                                  size: 64,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.isLoading)
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
            ),
          if (_isUploading)
            Container(
              color: Colors.black45,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          _uploadStatus,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
