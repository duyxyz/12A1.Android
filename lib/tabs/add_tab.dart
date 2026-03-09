import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../services/github_service.dart';
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
  List<XFile> _selectedImages = []; 

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi chọn ảnh: $e')),
        );
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
        List<int> existingIndexes = currentImages
            .map<int>((img) => img['index'] as int)
            .toList()
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
              title: Text('Đã chọn ${_selectedImages.length} ảnh'),
              actions: [
                IconButton(
                  onPressed: _clearSelection,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  tooltip: 'Xóa hết',
                ),
              ],
            )
          : null,
      body: _isUploading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const PulseSkeleton(width: 100, height: 100),
                  const SizedBox(height: 16),
                  Text(_uploadStatus, style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            )
          : _selectedImages.isNotEmpty
              ? Column(
                  children: [
                    Expanded(
                      child: GridView.builder(
                        physics: const ClampingScrollPhysics(),
                        padding: const EdgeInsets.all(8),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                            ),
                        itemCount: _selectedImages.length + 1,
                        itemBuilder: (context, index) {
                          if (index == _selectedImages.length) {
                            return InkWell(
                              onTap: _pickImage,
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outlineVariant,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.add_a_photo_outlined),
                              ),
                            );
                          }
                          return Stack(
                            children: [
                              Positioned.fill(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(
                                    File(_selectedImages[index].path),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () => _removeImage(index),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 18,
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
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _uploadImage,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Đăng tất cả ảnh'),
                        ),
                      ),
                    ),
                  ],
                )
              : Stack(
                  children: [
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            iconSize: 120, 
                            onPressed: _pickImage,
                            icon: const Icon(Icons.add_photo_alternate_outlined),
                          ),
                          const Text('Nhấn để chọn ảnh từ máy'),
                        ],
                      ),
                    ),
                    if (widget.isLoading)
                      const Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: LinearProgressIndicator(),
                      ),
                  ],
                ),
    );
  }
}
