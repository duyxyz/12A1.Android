import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;

import '../main.dart';
import '../data/models/gallery_image.dart';
import '../utils/haptics.dart';
import '../services/favorite_service.dart';
import 'expressive_loading_indicator.dart';

class FullScreenImageViewer extends StatefulWidget {
  final List<GalleryImage> images;
  final int initialIndex;

  const FullScreenImageViewer({
    super.key,
    required this.images,
    required this.initialIndex,
  });

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  late PageController _pageController;
  late int _currentIndex;
  
  bool _isFavorite = false;
  bool _isDownloading = false;
  bool _isDeleting = false;
  
  double _dismissOffset = 0.0;
  double _dismissOpacity = 1.0;
  double _dismissScale = 1.0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _checkFavorite();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  GalleryImage get currentImage => widget.images[_currentIndex];

  Future<void> _checkFavorite() async {
    final isFav = await FavoriteService.isFavorite(currentImage.sha);
    if (mounted) setState(() => _isFavorite = isFav);
  }

  Future<void> _toggleFavorite() async {
    AppHaptics.selectionClick();
    await FavoriteService.toggleFavorite(currentImage.sha);
    _checkFavorite();
  }

  Future<void> _downloadImage(BuildContext sheetContext) async {
    if (_isDownloading) return;
    Navigator.of(sheetContext).pop();
    setState(() => _isDownloading = true);
    AppHaptics.mediumImpact();

    try {
      final downloadUrl = '${currentImage.downloadUrl}?v=${currentImage.sha}';
      final response = await http.get(Uri.parse(downloadUrl));
      if (response.statusCode != 200) throw Exception("Server trả về lỗi: ${response.statusCode}");

      final Uint8List imageBytes = response.bodyBytes;
      if (imageBytes.isEmpty) throw Exception("Dữ liệu ảnh trống");

      final Uint8List jpegBytes = (await FlutterImageCompress.compressWithList(
        imageBytes, format: CompressFormat.jpeg, quality: 95,
      ))!;

      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) throw Exception("Bạn chưa cấp quyền lưu ảnh cho ứng dụng");
      }

      final fileName = p.basenameWithoutExtension(currentImage.downloadUrl);
      await Gal.putImageBytes(jpegBytes, name: fileName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu vào bộ sưu tập'), behavior: SnackBarBehavior.floating, backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: ${e.toString().replaceAll("Exception:", "").trim()}'), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _deleteImage(BuildContext sheetContext) async {
    if (_isDeleting) return;
    Navigator.of(sheetContext).pop();
    AppHaptics.lightImpact();
    
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Xóa ảnh này ?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Hủy')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Xóa'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;
    setState(() => _isDeleting = true);
    try {
      await AppDependencies.instance.homeViewModel.deleteImage(currentImage);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã xóa ảnh thành công')));
        if (widget.images.length <= 1) {
          Navigator.of(context).pop(true);
        } else {
          // If images remains, we stay in gallery but move or refresh? 
          // Simplest is to pop back to grid to refresh.
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi xóa ảnh: $e')));
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  void _showInfoDialog() {
    AppHaptics.lightImpact();
    final name = currentImage.name;
    final path = currentImage.path;
    final sizeInBytes = currentImage.size;
    final sizeFormatted = sizeInBytes > 1024 * 1024
        ? '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(2)} MB'
        : '${(sizeInBytes / 1024).toStringAsFixed(2)} KB';
    final type = p.extension(name).replaceAll('.', '').toUpperCase();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thông tin ảnh'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Tên file', name),
            _buildInfoRow('Định dạng', type.isEmpty ? 'Không rõ' : type),
            _buildInfoRow('Kích thước', sizeFormatted),
            _buildInfoRow('Đường dẫn', path),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Đóng')),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          Text(value, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _dismissOffset.abs() < 10,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // Logic for handling back if needed (already handled by system mostly)
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // Dynamic Background
            Positioned.fill(
              child: Opacity(
                opacity: _dismissOpacity,
                child: Container(color: Colors.black),
              ),
            ),
            
            // Image Content
            GestureDetector(
              onVerticalDragUpdate: (details) {
                setState(() {
                  _dismissOffset += details.delta.dy;
                  _dismissOpacity = (1.0 - (_dismissOffset.abs() / 400)).clamp(0.0, 1.0);
                  _dismissScale = (1.0 - (_dismissOffset.abs() / 1500)).clamp(0.6, 1.0);
                });
              },
              onVerticalDragEnd: (details) {
                if (_dismissOffset.abs() > 100 || details.velocity.pixelsPerSecond.distance > 400) {
                  Navigator.of(context).pop();
                } else {
                  setState(() {
                    _dismissOffset = 0.0;
                    _dismissOpacity = 1.0;
                    _dismissScale = 1.0;
                  });
                }
              },
              onLongPress: () {
                AppHaptics.mediumImpact();
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  builder: (context) => _buildBottomSheet(context),
                );
              },
              child: Transform.translate(
                offset: Offset(0, _dismissOffset),
                child: Transform.scale(
                  scale: _dismissScale,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: widget.images.length,
                    onPageChanged: (index) {
                      setState(() => _currentIndex = index);
                      _checkFavorite();
                      AppHaptics.lightImpact();
                    },
                    itemBuilder: (context, index) {
                      final image = widget.images[index];
                      return InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 3.0,
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: image.aspectRatio,
                            child: CachedNetworkImage(
                              imageUrl: '${image.downloadUrl}?v=${image.sha}',
                              fit: BoxFit.contain,
                              fadeInDuration: const Duration(milliseconds: 200),
                              fadeOutDuration: const Duration(milliseconds: 200),
                              placeholder: (context, url) => const Center(
                                child: ExpressiveLoadingIndicator(isContained: true),
                              ),
                              errorWidget: (context, url, error) => const Icon(Icons.error, color: Colors.white24),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
  
            if (_isDownloading) _buildLoadingOverlay('Đang lưu ảnh...'),
            if (_isDeleting) _buildLoadingOverlay('Đang xóa ảnh...'),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSheet(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.only(bottom: 32, top: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 32,
            height: 4,
            decoration: BoxDecoration(color: Colors.grey.withOpacity(0.2), borderRadius: BorderRadius.circular(2)),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildIconAction(Icons.download_rounded, Colors.blue, () => _downloadImage(context), isDark),
              _buildIconAction(
                _isFavorite ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
                Colors.pink,
                () { Navigator.pop(context); _toggleFavorite(); },
                isDark,
              ),
              _buildIconAction(Icons.info_outline_rounded, Colors.teal, () { Navigator.pop(context); _showInfoDialog(); }, isDark),
              _buildIconAction(Icons.delete_outline_rounded, Colors.red, () => _deleteImage(context), isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIconAction(IconData icon, Color color, VoidCallback onPressed, bool isDark) {
    return IconButton.filledTonal(
      onPressed: onPressed,
      icon: Icon(icon, size: 26),
      style: IconButton.styleFrom(
        backgroundColor: color.withOpacity(0.2),
        foregroundColor: color,
        padding: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildLoadingOverlay(String text) {
    return Container(
      color: Colors.black45,
      child: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const ExpressiveLoadingIndicator(isContained: true),
              const SizedBox(height: 16),
              Text(text),
            ]),
          ),
        ),
      ),
    );
  }
}
