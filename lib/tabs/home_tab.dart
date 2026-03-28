import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../main.dart';
import '../widgets/image_grid_item.dart';
import '../widgets/error_view.dart';
import '../widgets/pulse_skeleton.dart';

class HomeTab extends StatefulWidget {
  final List<Map<String, dynamic>> images;
  final bool isLoading;
  final String error;
  final Future<void> Function() onRefresh;
  final ScrollController scrollController;

  const HomeTab({
    super.key,
    required this.images,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
    required this.scrollController,
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.error.isNotEmpty) {
      return ErrorView(
        message: 'Lỗi: ${widget.error}',
        onRetry: widget.onRefresh,
        isFullScreen: false,
      );
    }

    final bool showSkeletons = widget.isLoading && widget.images.isEmpty;

    return Stack(
      children: [
        ValueListenableBuilder<int>(
          valueListenable: MyApp.gridColumnsNotifier,
          builder: (context, gridCols, _) {
            if (showSkeletons) {
              return MasonryGridView.count(
                padding: const EdgeInsets.all(4.0),
                crossAxisCount: gridCols,
                mainAxisSpacing: 4.0,
                crossAxisSpacing: 4.0,
                itemCount: 12,
                itemBuilder: (context, index) {
                  final ratios = [1.0, 1.5, 0.75, 1.2, 0.8, 1.4, 0.9, 1.1];
                  final ratio = ratios[index % ratios.length];
                  return AspectRatio(
                    aspectRatio: ratio,
                    child: const PulseSkeleton(),
                  );
                },
              );
            }

            return MasonryGridView.count(
              controller: widget.scrollController,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(4.0),
              crossAxisCount: gridCols,
              mainAxisSpacing: 4.0,
              crossAxisSpacing: 4.0,
              itemCount: widget.images.length,
              itemBuilder: (context, index) {
                final imageUrl = widget.images[index]['download_url'];
                final aspectRatio =
                    widget.images[index]['aspect_ratio'] as double;
                return ImageGridItem(
                  imageUrl: imageUrl,
                  aspectRatio: aspectRatio,
                  imageMap: widget.images[index],
                  heroTag: 'home-${widget.images[index]['sha']}',
                );
              },
            );
          },
        ),
        // Hiện thanh loading ở dưới chỉ khi ĐÃ CÓ ảnh (tức là nạp thêm hoặc làm mới)
        if (widget.isLoading && widget.images.isNotEmpty)
          const Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(child: LinearProgressIndicator()),
          ),
      ],
    );
  }
}
