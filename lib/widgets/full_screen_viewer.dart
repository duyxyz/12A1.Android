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
  final GalleryImage image;
  final String heroTag;

  const FullScreenImageViewer({
    super.key,
    required this.image,
    required this.heroTag,
  });

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer>
    with TickerProviderStateMixin {
  double _scale = 1.0;
  double _baseScale = 1.0;
  Offset _offset = Offset.zero;

  AnimationController? _resetAnim;

  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _checkFavorite();
  }

  Future<void> _checkFavorite() async {
    final isFav = await FavoriteService.isFavorite(widget.image.sha);
    if (mounted) setState(() => _isFavorite = isFav);
  }

  Future<void> _toggleFavorite() async {
    AppHaptics.selectionClick();
    await FavoriteService.toggleFavorite(widget.image.sha);
    _checkFavorite();
  }

  @override
  void dispose() {
    _resetAnim?.dispose();
    super.dispose();
  }

  void _onScaleStart(ScaleStartDetails _) {
    _resetAnim?.stop();
    _baseScale = _scale;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      if (details.pointerCount >= 2) {
        final newScale = (_baseScale * details.scale).clamp(0.5, 5.0);
        final double k = newScale / _scale;

        final screenSize = MediaQuery.of(context).size;
        final center = Offset(screenSize.width / 2, screenSize.height / 2);
        final focal = details.localFocalPoint;
        _offset = (focal - center) * (1 - k) + _offset * k;
        _scale = newScale;
      } else if (_scale > 1.01) {
        _offset += details.focalPointDelta;
      }
    });
  }

  void _onScaleEnd(ScaleEndDetails _) {
    if (_scale < 1.0) {
      _animateReset(targetScale: 1.0, targetOffset: Offset.zero);
    } else if (_scale <= 1.05 && _offset.distance > 1) {
      _animateReset(targetScale: 1.0, targetOffset: Offset.zero);
    }
  }

  void _onDoubleTap() {
    if (_scale > 1.05) {
      _animateReset(targetScale: 1.0, targetOffset: Offset.zero);
    } else {
      _animateReset(targetScale: 2.5, targetOffset: Offset.zero);
    }
  }

  bool _isDownloading = false;

  Future<void> _downloadImage(BuildContext sheetContext) async {
    if (_isDownloading) return;
    Navigator.of(sheetContext).pop();
    setState(() => _isDownloading = true);
    AppHaptics.mediumImpact();

    try {
      final downloadUrl = '${widget.image.downloadUrl}?v=${widget.image.sha}';
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

      final fileName = p.basenameWithoutExtension(widget.image.downloadUrl);
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

  bool _isDeleting = false;

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
      await AppDependencies.instance.homeViewModel.deleteImage(widget.image);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã xóa ảnh thành công')));
        Navigator.of(context).pop(true);
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
    final name = widget.image.name;
    final path = widget.image.path;
    final sizeInBytes = widget.image.size;
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

  void _animateReset({required double targetScale, required Offset targetOffset}) {
    final startScale = _scale;
    final startOffset = _offset;
    _resetAnim?.dispose();
    _resetAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    final curved = CurvedAnimation(parent: _resetAnim!, curve: Curves.easeOut);
    curved.addListener(() {
      setState(() {
        final t = curved.value;
        _scale = startScale + (targetScale - startScale) * t;
        _offset = Offset.lerp(startOffset, targetOffset, t)!;
      });
    });
    _resetAnim!.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          GestureDetector(
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            onDoubleTap: _onDoubleTap,
            onLongPress: () {
              AppHaptics.mediumImpact();
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                builder: (context) => _buildCompactBottomSheet(context),
              );
            },
            behavior: HitTestBehavior.opaque,
            child: SizedBox.expand(
              child: Center(
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..translate(_offset.dx, _offset.dy)
                    ..scale(_scale),
                  child: AspectRatio(
                    aspectRatio: widget.image.aspectRatio,
                    child: CachedNetworkImage(
                      imageUrl: '${widget.image.downloadUrl}?v=${widget.image.sha}',
                      fit: BoxFit.cover,
                      width: double.infinity, height: double.infinity,
                      errorWidget: (context, url, error) => Icon(Icons.error, color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_isDownloading) _buildLoadingOverlay('Đang lưu ảnh...'),
          if (_isDeleting) _buildLoadingOverlay('Đang xóa ảnh...'),
        ],
      ),
    );
  }

  Widget _buildCompactBottomSheet(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildIconActionButton(
                tooltip: 'Tai xuong',
                icon: Icons.download_rounded,
                color: Colors.blue,
                isDark: isDark,
                onPressed: () => _downloadImage(context),
              ),
              _buildIconActionButton(
                tooltip: _isFavorite ? 'Bo thich' : 'Yeu thich',
                icon: _isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: Colors.pink,
                isDark: isDark,
                onPressed: () {
                  Navigator.pop(context);
                  _toggleFavorite();
                },
              ),
              _buildIconActionButton(
                tooltip: 'Thong tin',
                icon: Icons.info_outline_rounded,
                color: Colors.teal,
                isDark: isDark,
                onPressed: () {
                  Navigator.pop(context);
                  _showInfoDialog();
                },
              ),
              _buildIconActionButton(
                tooltip: 'Xoa anh',
                icon: Icons.delete_outline_rounded,
                color: Colors.red,
                isDark: isDark,
                onPressed: () => _deleteImage(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIconActionButton({
    required String tooltip,
    required IconData icon,
    required Color color,
    required bool isDark,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: color.withOpacity(0.2),
            foregroundColor: isDark ? Colors.white : color,
            minimumSize: const Size(56, 56),
            padding: const EdgeInsets.all(16),
            shape: const CircleBorder(),
          ),
          child: Icon(icon, size: 24),
        ),
      ),
    );
  }

  Widget _buildBottomSheet(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.only(bottom: 32),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(margin: const EdgeInsets.symmetric(vertical: 12), width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Row(children: [
                  Expanded(child: _buildActionBtn('Tải xuống', Colors.blue, () => _downloadImage(context), isDark)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildActionBtn(_isFavorite ? 'Bỏ thích' : 'Yêu thích', Colors.pink, () { Navigator.pop(context); _toggleFavorite(); }, isDark)),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _buildActionBtn('Thông tin', Colors.grey, () { Navigator.pop(context); _showInfoDialog(); }, isDark)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildActionBtn('Xóa ảnh', Colors.red, () => _deleteImage(context), isDark)),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBtn(String label, Color color, VoidCallback onPressed, bool isDark) {
    return FilledButton.tonal(
      onPressed: onPressed,
      style: FilledButton.styleFrom(backgroundColor: color.withOpacity(0.2), foregroundColor: isDark ? Colors.white : color, padding: const EdgeInsets.symmetric(vertical: 16)),
      child: Text(label),
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
