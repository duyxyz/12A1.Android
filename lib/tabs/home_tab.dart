import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../logic/viewmodels/home_view_model.dart';
import '../main.dart';
import '../widgets/error_view.dart';
import '../widgets/expressive_loading_indicator.dart';
import '../widgets/image_grid_item.dart';

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
    final showSkeletons = viewModel.isLoading && viewModel.images.isEmpty;
    final gridConfig = AppDependencies.instance.configViewModel;
    final appBarBorder = Theme.of(context).dividerColor.withValues(alpha: 0.2);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        shadowColor: Colors.transparent,
        titleSpacing: 16,
        title: const Text(
          'Gay Group',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${viewModel.images.length} ảnh',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: appBarBorder,
          ),
        ),
      ),
      body: Stack(
        children: [
          if (viewModel.error.isNotEmpty)
            ErrorView(
              message: 'Lỗi: ${viewModel.error}',
              onRetry: viewModel.loadImages,
              isFullScreen: false,
            )
          else
            ListenableBuilder(
              listenable: gridConfig,
              builder: (context, _) {
                if (showSkeletons) {
                  return const Center(
                    child: ExpressiveLoadingIndicator(isContained: true),
                  );
                }

                return MasonryGridView.count(
                  controller: scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(4),
                  crossAxisCount: gridConfig.gridColumns,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  itemCount: viewModel.images.length,
                  itemBuilder: (context, index) {
                    final image = viewModel.images[index];
                    return ImageGridItem(
                      image: image,
                      heroTag: 'home-${image.index}',
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
      ),
    );
  }
}
