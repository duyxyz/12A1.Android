import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../main.dart';
import '../logic/viewmodels/home_view_model.dart';
import '../widgets/image_grid_item.dart';
import '../widgets/error_view.dart';
import '../widgets/expressive_loading_indicator.dart';

class HomeTab extends StatelessWidget {
  final HomeViewModel viewModel;
  final ScrollController scrollController;

  const HomeTab({
    super.key,
    required this.viewModel,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    if (viewModel.error.isNotEmpty) {
      return ErrorView(
        message: 'Lỗi: ${viewModel.error}',
        onRetry: viewModel.loadImages,
        isFullScreen: false,
      );
    }

    final bool showSkeletons = viewModel.isLoading && viewModel.images.isEmpty;
    final gridConfig = AppDependencies.instance.configViewModel;

    return Stack(
      children: [
        ListenableBuilder(
          listenable: gridConfig,
          builder: (context, _) {
            if (showSkeletons) {
              return const Center(
                child: ExpressiveLoadingIndicator(isContained: true),
              );
            }

            return MasonryGridView.count(
              key: const PageStorageKey<String>('home-grid'),
              controller: scrollController,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(4.0),
              crossAxisCount: gridConfig.gridColumns,
              mainAxisSpacing: 4.0,
              crossAxisSpacing: 4.0,
              itemCount: viewModel.images.length,
              itemBuilder: (context, index) {
                final image = viewModel.images[index];
                return ImageGridItem(
                  key: ValueKey('home-${image.sha}'),
                  image: image,
                );
              },
            );
          },
        ),
        if (viewModel.isLoading && viewModel.images.isNotEmpty)
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
