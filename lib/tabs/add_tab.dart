import 'dart:io';
import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import '../main.dart';
import '../logic/viewmodels/home_view_model.dart';
import '../utils/haptics.dart';
import '../widgets/error_view.dart';
import '../widgets/expressive_loading_indicator.dart';

class AddTab extends StatefulWidget {
  final HomeViewModel viewModel;

  const AddTab({
    super.key,
    required this.viewModel,
  });

  @override
  State<AddTab> createState() => AddTabState();
}

class AddTabState extends State<AddTab> {
  bool _isLocalLoading = false;
  String _uploadStatus = "";
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _selectedImages = [];

  Future<void> pickImage() async {
    AppHaptics.lightImpact();
    try {
      final images = await _picker.pickMultiImage();
      if (images.isNotEmpty) {
        setState(() {
          _selectedImages.addAll(images);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi chọn ảnh: $e')));
      }
    }
  }

  Future<void> _uploadImages() async {
    AppHaptics.lightImpact();
    if (_selectedImages.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Đăng ${_selectedImages.length} ảnh?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Đăng')),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isLocalLoading = true;
      _uploadStatus = "Bắt đầu tải lên...";
    });

    try {
      for (int i = 0; i < _selectedImages.length; i++) {
        final image = _selectedImages[i];
        if (!mounted) return;
        setState(() {
          _uploadStatus = "Đang xử lý ${i + 1}/${_selectedImages.length}...";
        });

        final compressedBytes = await FlutterImageCompress.compressWithFile(
          image.path,
          minWidth: 1920,
          minHeight: 1920,
          quality: 80,
          format: CompressFormat.webp,
        );

        if (compressedBytes == null) continue;

        final decodedImage = await decodeImageFromList(compressedBytes);
        final filename = '${DateTime.now().millisecondsSinceEpoch}.webp';

        await widget.viewModel.uploadImage(
          filename,
          compressedBytes,
          decodedImage.width,
          decodedImage.height,
        );
        decodedImage.dispose();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã tải tất cả ảnh lên thành công!')),
        );
        setState(() {
          _selectedImages.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi tải lên: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLocalLoading = false);
      }
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
    if (widget.viewModel.error.isNotEmpty) {
      return ErrorView(
        message: 'Lỗi nạp dữ liệu: ${widget.viewModel.error}',
        onRetry: widget.viewModel.loadImages,
        isFullScreen: false,
      );
    }

    final appBarTextColor = Theme.of(context).colorScheme.primary;
    final appBarDisabledColor =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38);
    final canClearOrUpload = _selectedImages.isNotEmpty && !_isLocalLoading;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        shadowColor: Colors.transparent,
        leading: IconButton(
          onPressed: canClearOrUpload ? _clearSelection : null,
          icon: Icon(
            Icons.delete_sweep_rounded,
            color: canClearOrUpload ? appBarTextColor : appBarDisabledColor,
          ),
          tooltip: 'Xóa hết',
        ),
        title: Text(
          'Đã chọn ${_selectedImages.length} ảnh',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: canClearOrUpload ? appBarTextColor : appBarDisabledColor,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilledButton.tonal(
              onPressed: canClearOrUpload ? _uploadImages : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                foregroundColor: appBarTextColor,
              ),
              child: const Text('Tải lên', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Theme.of(context).dividerColor.withValues(alpha: 0.2), height: 1.0),
        ),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                if (widget.viewModel.isLoading || _isLocalLoading) const LinearProgressIndicator(),
                Expanded(
                  child: GridView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _selectedImages.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _selectedImages.length) {
                        return InkWell(
                          onTap: pickImage,
                          borderRadius: BorderRadius.circular(16),
                          child: DottedBorder(
                            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                            strokeWidth: 2,
                            dashPattern: const [6, 4],
                            borderType: BorderType.RRect,
                            radius: const Radius.circular(16),
                            padding: EdgeInsets.zero,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Center(
                                child: Icon(Icons.add_rounded, size: 32, color: Theme.of(context).colorScheme.primary),
                              ),
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
                                border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.file(File(_selectedImages[index].path), fit: BoxFit.cover),
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
                                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
                                child: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_isLocalLoading)
            Container(
              color: Colors.black45,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const ExpressiveLoadingIndicator(isContained: true),
                        const SizedBox(height: 16),
                        Text(_uploadStatus, style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
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
