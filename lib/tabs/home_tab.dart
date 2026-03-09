import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../main.dart';
import '../widgets/image_grid_item.dart';
import '../widgets/error_view.dart';
import '../utils/haptics.dart';

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

    return Stack(
      children: [
        ValueListenableBuilder<int>(
          valueListenable: MyApp.gridColumnsNotifier,
          builder: (context, gridCols, _) {
            return MasonryGridView.count(
              controller: widget.scrollController,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.all(4.0),
              crossAxisCount: gridCols,
              mainAxisSpacing: 4.0,
              crossAxisSpacing: 4.0,
              itemCount: widget.images.length,
              itemBuilder: (context, index) {
                final imageUrl = widget.images[index]['download_url'];
                final aspectRatio = widget.images[index]['aspect_ratio'] as double;
    
                return ImageGridItem(imageUrl: imageUrl, aspectRatio: aspectRatio);
              },
            );
          },
        ),
        // Thanh loading duy nhất nằm ở cạnh dưới cho mọi trường hợp nạp dữ liệu
        if (widget.isLoading)
          const Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: LinearProgressIndicator(),
            ),
          ),
      ],
    );
  }
}
