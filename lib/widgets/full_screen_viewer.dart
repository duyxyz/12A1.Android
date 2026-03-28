import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;

import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import '../utils/haptics.dart';
import '../services/github_service.dart';
import '../services/supabase_service.dart';
import '../services/favorite_service.dart';
import 'expressive_loading_indicator.dart';

class FullScreenImageViewer extends StatefulWidget {
  final String imageUrl;
  final double aspectRatio;
  final Map<String, dynamic>? imageMap;
  final String heroTag;

  const FullScreenImageViewer({
    super.key,
    required this.imageUrl,
    required this.aspectRatio,
    this.imageMap,
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
  Offset _baseOffset = Offset.zero;
  Offset _startFocalPoint = Offset.zero;

  bool _isDismissing = false;
  Offset _dismissOffset = Offset.zero;
  double _dismissScale = 1.0;

  AnimationController? _resetAnim;

  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _checkFavorite();
  }

  Future<void> _checkFavorite() async {
    if (widget.imageMap != null && widget.imageMap!['sha'] != null) {
      final isFav = await FavoriteService.isFavorite(widget.imageMap!['sha']);
      if (mounted) setState(() => _isFavorite = isFav);
    }
  }

  Future<void> _toggleFavorite() async {
    if (widget.imageMap == null || widget.imageMap!['sha'] == null) return;
    AppHaptics.selectionClick();
    await FavoriteService.toggleFavorite(widget.imageMap!['sha']);
    _checkFavorite();
  }

  @override
  void dispose() {
    _resetAnim?.dispose();
    super.dispose();
  }

  void _onScaleStart(ScaleStartDetails details) {
    _resetAnim?.stop();
    _baseScale = _scale;
    _baseOffset = _offset;
    _startFocalPoint = details.localFocalPoint;

    _isDismissing =
        details.pointerCount == 1 && _scale <= 1.01 && _offset.distance < 5;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      if (details.pointerCount >= 2) {
        if (_isDismissing) {
          _isDismissing = false;
          _dismissOffset = Offset.zero;
          _dismissScale = 1.0;
          _baseScale = _scale;
          _baseOffset = _offset;
          _startFocalPoint = details.localFocalPoint;
          return;
        }

        final newScale = (_baseScale * details.scale).clamp(0.5, 5.0);
        final double k = newScale / _scale;

        final screenSize = MediaQuery.of(context).size;
        final center = Offset(screenSize.width / 2, screenSize.height / 2);
        final focal = details.localFocalPoint;
        _offset = (focal - center) * (1 - k) + _offset * k;
        _scale = newScale;
      } else if (_isDismissing) {
        _dismissOffset += details.focalPointDelta;
        _dismissScale = (1.0 - (_dismissOffset.distance / 1500)).clamp(
          0.6,
          1.0,
        );
      } else if (_scale > 1.01) {
        _offset += details.focalPointDelta;
      }
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_isDismissing) {
      _isDismissing = false;
      if (_dismissOffset.distance > 100) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _dismissOffset = Offset.zero;
          _dismissScale = 1.0;
        });
      }
      return;
    }

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

    setState(() {
      _isDownloading = true;
    });
    AppHaptics.mediumImpact();

    try {
      final downloadUrl = widget.imageMap != null && widget.imageMap!['sha'] != null 
          ? '${widget.imageUrl}?v=${widget.imageMap!['sha']}'
          : widget.imageUrl;
      final response = await http.get(Uri.parse(downloadUrl));
      if (response.statusCode != 200) {
        throw Exception("Server trả về lỗi: ${response.statusCode}");
      }

      final Uint8List imageBytes = response.bodyBytes;
      if (imageBytes.isEmpty) throw Exception("Dữ liệu ảnh trống");

      final Uint8List jpegBytes = await FlutterImageCompress.compressWithList(
        imageBytes,
        format: CompressFormat.jpeg,
        quality: 95,
      );

      if (jpegBytes == null || jpegBytes.isEmpty) {
        throw Exception("Không thể chuyển đổi định dạng ảnh");
      }

      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted)
          throw Exception("Bạn chưa cấp quyền lưu ảnh cho ứng dụng");
      }

      final fileName = p.basenameWithoutExtension(widget.imageUrl);
      await Gal.putImageBytes(jpegBytes, name: fileName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã lưu vào bộ sưu tập'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint("Download error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Lỗi: ${e.toString().replaceAll("Exception:", "").trim()}',
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  bool _isDeleting = false;

  Future<void> _deleteImage(BuildContext sheetContext) async {
    if (widget.imageMap == null || _isDeleting) return;

    Navigator.of(sheetContext).pop();

    AppHaptics.lightImpact();
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Xóa ảnh này ?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
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
      final img = widget.imageMap!;
      if (img['path'] != null && img['sha'] != null) {
        await GithubService.deleteImage(img['path'], img['sha']);
      }
      if (img['index'] != null) {
        await SupabaseService.deleteImageMetadata(img['index'] as int);
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã xóa ảnh thành công')));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi xóa ảnh: $e')));
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  void _showInfoDialog() {
    AppHaptics.lightImpact();
    final img = widget.imageMap;
    if (img == null) return;

    final name = img['name'] ?? 'Không tên';
    final path = img['path'] ?? 'Không rõ';
    final sizeInBytes = img['size'] as int? ?? 0;
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
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
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          Text(value, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  void _animateReset({
    required double targetScale,
    required Offset targetOffset,
  }) {
    final startScale = _scale;
    final startOffset = _offset;

    _resetAnim?.dispose();
    _resetAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

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
    final double bgOpacity = _isDismissing
        ? (1.0 - (_dismissOffset.distance / 300)).clamp(0.0, 1.0)
        : 1.0;

    return Scaffold(
      backgroundColor: Theme.of(
        context,
      ).scaffoldBackgroundColor.withOpacity(bgOpacity),
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
                builder: (context) => Container(
                  padding: const EdgeInsets.only(bottom: 32),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.tonalIcon(
                                     onPressed: () => _downloadImage(context),
                                    icon: const Icon(Icons.download_rounded),
                                    label: const Text('Tải xuống'),
                                    style: FilledButton.styleFrom(
                                      foregroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.white : null,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: FilledButton.icon(
                                     onPressed: () => _deleteImage(context),
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('Xóa ảnh'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.red.withValues(
                                        alpha: Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? 0.7
                                            : 0.15,
                                      ),
                                      foregroundColor: Theme.of(context)
                                                  .brightness ==
                                              Brightness.dark
                                          ? Colors.white
                                          : Colors.red,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.tonalIcon(
                                     onPressed: () {
                                       Navigator.of(context).pop();
                                       // Add a small delay to avoid race condition with Sheet closing and Hero rebuild
                                       Future.delayed(
                                         const Duration(milliseconds: 100),
                                        () => _toggleFavorite(),
                                      );
                                    },
                                    icon: Icon(
                                      _isFavorite
                                          ? Icons.favorite_rounded
                                          : Icons.favorite_outline_rounded,
                                    ),
                                    label: Text(
                                      _isFavorite ? 'Bỏ thích' : 'Yêu thích',
                                    ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor:
                                          Colors.pink.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.35 : 0.15),
                                      foregroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.pink,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: FilledButton.tonalIcon(
                                     onPressed: () {
                                       Navigator.of(context).pop();
                                       _showInfoDialog();
                                     },
                                    icon: const Icon(Icons.info_outline_rounded),
                                    label: const Text('Thông tin'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor:
                                          Colors.grey.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.35 : 0.15),
                                      foregroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.grey[800],
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            behavior: HitTestBehavior.opaque,
            child: SizedBox.expand(
              child: Transform.translate(
                offset: _isDismissing ? _dismissOffset : Offset.zero,
                child: Transform.scale(
                  scale: _isDismissing ? _dismissScale : 1.0,
                  child: Center(
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..translate(_offset.dx, _offset.dy)
                        ..scale(_scale),
                      child: Hero(
                        tag: widget.heroTag,
                        child: AspectRatio(
                          aspectRatio: widget.aspectRatio,
                          child: CachedNetworkImage(
                            imageUrl: widget.imageMap != null && widget.imageMap!['sha'] != null
                                ? '${widget.imageUrl}?v=${widget.imageMap!['sha']}'
                                : widget.imageUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorWidget: (context, url, error) => Icon(
                              Icons.error,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_isDownloading)
            Container(
              color: Colors.black45,
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ExpressiveLoadingIndicator(isContained: true),
                        SizedBox(height: 16),
                        Text('Đang lưu ảnh...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_isDeleting)
            Container(
              color: Colors.black45,
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ExpressiveLoadingIndicator(isContained: true),
                        SizedBox(height: 16),
                        Text('Đang xóa ảnh...'),
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
