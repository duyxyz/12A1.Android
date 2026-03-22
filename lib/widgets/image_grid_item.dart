import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'pulse_skeleton.dart';
import '../utils/haptics.dart';
import 'full_screen_viewer.dart';

class ImageGridItem extends StatefulWidget {
  final String imageUrl;
  final double aspectRatio;
  final Map<String, dynamic>? imageMap;

  const ImageGridItem({super.key, required this.imageUrl, required this.aspectRatio, this.imageMap});

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

    return InkWell(
      onTap: () async {
        AppHaptics.selectionClick();
        
        final RenderBox? box = context.findRenderObject() as RenderBox?;
        if (box != null) {
          final position = box.localToGlobal(Offset.zero);
          final bottom = position.dy + box.size.height;
          final screenHeight = MediaQuery.of(context).size.height;
          
          const navBarHeight = 80.0;
          final viewportBottom = screenHeight - navBarHeight;

          if (bottom > viewportBottom) {
            await Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 300),
              alignment: 1.0, 
              curve: Curves.easeInOut,
            );
          } else if (position.dy < 0) {
            await Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 300),
              alignment: 0.0,
              curve: Curves.easeInOut,
            );
          }
        }

        if (!mounted) return;

        Navigator.of(context).push(
          PageRouteBuilder(
            opaque: false,
            barrierColor: Colors.black,
            pageBuilder: (context, animation, secondaryAnimation) {
              return FullScreenImageViewer(
                imageUrl: widget.imageUrl,
                aspectRatio: widget.aspectRatio,
                imageMap: widget.imageMap,
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
          aspectRatio: widget.aspectRatio,
          child: Hero(
            tag: widget.imageUrl,
            child: CachedNetworkImage(
              imageUrl: widget.imageUrl,
              fit: BoxFit.cover,
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
