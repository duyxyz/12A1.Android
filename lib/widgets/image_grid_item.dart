import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'pulse_skeleton.dart';
import '../data/models/gallery_image.dart';
import '../utils/haptics.dart';
import 'full_screen_viewer.dart';

class ImageGridItem extends StatefulWidget {
  final GalleryImage image;
  final String? heroTag;

  const ImageGridItem({
    super.key,
    required this.image,
    this.heroTag,
  });

  @override
  State<ImageGridItem> createState() => _ImageGridItemState();
}

class _ImageGridItemState extends State<ImageGridItem>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; 

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return GestureDetector(
      onTap: () async {
        AppHaptics.selectionClick();
        
        final RenderBox? box = context.findRenderObject() as RenderBox?;
        if (box != null) {
          final position = box.localToGlobal(Offset.zero);
          final bottom = position.dy + box.size.height;
          final screenHeight = MediaQuery.of(context).size.height;
          
          const navBarHeight = 80.0;
          final viewportBottom = screenHeight - navBarHeight;

          final topThreshold = MediaQuery.of(context).padding.top + kToolbarHeight;
          bool needsDelay = false;

          if (bottom > viewportBottom) {
            Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 150),
              alignment: 1.0, 
              curve: Curves.easeOut,
            );
            needsDelay = true;
          } else if (position.dy < topThreshold) {
            Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 150),
              alignment: 0.0,
              curve: Curves.easeOut,
            );
            needsDelay = true;
          }
          
          if (needsDelay) {
            await Future.delayed(const Duration(milliseconds: 150));
          }
        }

        if (!mounted) return;

        Navigator.of(context).push(
          PageRouteBuilder(
            opaque: false,
            barrierColor: Colors.transparent,
            pageBuilder: (context, animation, secondaryAnimation) {
              return FullScreenImageViewer(
                image: widget.image,
                heroTag: widget.heroTag ?? widget.image.downloadUrl,
              );
            },
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      },
      child: ClipRRect(
        child: AspectRatio(
          aspectRatio: widget.image.aspectRatio,
          child: Hero(
            tag: widget.heroTag ?? widget.image.downloadUrl,
            child: CachedNetworkImage(
              imageUrl: '${widget.image.downloadUrl}?v=${widget.image.sha}',
              fit: BoxFit.cover,
              // Giới hạn kích thước giải mã để tiết kiệm RAM và CPU
              // 400px là mức an toàn cho Grid 2-4 cột trên di động
              memCacheWidth: (400 * MediaQuery.of(context).devicePixelRatio).round(),
              fadeInDuration: const Duration(milliseconds: 300),
              fadeOutDuration: const Duration(milliseconds: 300),
              placeholder: (context, url) => const PulseSkeleton(),
              errorWidget: (context, url, error) => Container(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Icon(
                  Icons.image_not_supported_rounded,
                  color: Theme.of(context).colorScheme.error,
                  size: 24,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
