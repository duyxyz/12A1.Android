import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:shimmer/shimmer.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import '../utils/haptics.dart';

class FullScreenImageViewer extends StatefulWidget {
  final String imageUrl;
  final double aspectRatio;

  const FullScreenImageViewer({
    super.key,
    required this.imageUrl,
    required this.aspectRatio,
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
        _dismissScale =
            (1.0 - (_dismissOffset.distance / 1500)).clamp(0.6, 1.0);
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

  Future<void> _downloadImage() async {
    if (_isDownloading) return;
    Navigator.pop(context);

    setState(() {
      _isDownloading = true;
    });
    AppHaptics.mediumImpact();

    try {
      final response = await http.get(Uri.parse(widget.imageUrl));
      if (response.statusCode != 200) {
        throw Exception("Server trả về lỗi: ${response.statusCode}");
      }
      
      final Uint8List imageBytes = response.bodyBytes;
      if (imageBytes.isEmpty) throw Exception("Dữ liệu ảnh trống");

      final Uint8List? jpegBytes = await FlutterImageCompress.compressWithList(
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
        if (!granted) throw Exception("Bạn chưa cấp quyền lưu ảnh cho ứng dụng");
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
            content: Text('Lỗi: ${e.toString().replaceAll("Exception:", "").trim()}'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _animateReset({required double targetScale, required Offset targetOffset}) {
    final startScale = _scale;
    final startOffset = _offset;

    _resetAnim?.dispose();
    _resetAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    final curved = CurvedAnimation(
      parent: _resetAnim!,
      curve: Curves.easeOut,
    );

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
      backgroundColor: Colors.black.withValues(alpha: bgOpacity),
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
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.download_rounded),
                        title: const Text('Tải xuống'),
                        onTap: _downloadImage,
                      ),
                      const SizedBox(height: 20),
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
                        tag: widget.imageUrl,
                        child: AspectRatio(
                          aspectRatio: widget.aspectRatio,
                          child: CachedNetworkImage(
                            imageUrl: widget.imageUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorWidget: (context, url, error) =>
                                const Icon(Icons.error, color: Colors.white),
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
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Đang lưu ảnh...'),
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
