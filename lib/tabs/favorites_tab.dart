import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../data/models/gallery_image.dart';
import '../main.dart';
import '../services/favorite_service.dart';
import '../widgets/image_grid_item.dart';

class FavoritesTab extends StatelessWidget {
  final List<GalleryImage> allImages;
  final bool isLoading;

  const FavoritesTab({
    super.key,
    required this.allImages,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final config = AppDependencies.instance.configViewModel;
    final appBarBorder = Theme.of(context).dividerColor.withValues(alpha: 0.2);
    final appBarTextColor = Theme.of(context).colorScheme.primary;

    return ValueListenableBuilder<Set<String>>(
      valueListenable: FavoriteService.favoritesNotifier,
      builder: (context, favoriteShas, _) {
        final favoriteImages = allImages
            .where((img) => favoriteShas.contains(img.sha))
            .toList();

        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: Theme.of(context).colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            elevation: 0,
            shadowColor: Colors.transparent,
            titleSpacing: 16,
            title: Text(
              'Yêu thích',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: appBarTextColor,
              ),
            ),
            centerTitle: false,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    '${favoriteImages.length} ảnh',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: appBarTextColor,
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
          body: _buildBody(context, config, favoriteImages),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    dynamic config,
    List<GalleryImage> favoriteImages,
  ) {
    if (favoriteImages.isEmpty && !isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.favorite_border_rounded,
              size: 42,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.45),
            ),
            const SizedBox(height: 16),
            Text(
              'Chưa có ảnh yêu thích nào',
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.75),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return ListenableBuilder(
      listenable: config,
      builder: (context, _) {
        return MasonryGridView.count(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(4),
          crossAxisCount: config.gridColumns,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          itemCount: favoriteImages.length,
          itemBuilder: (context, index) {
            final image = favoriteImages[index];
            return ImageGridItem(
              image: image,
              heroTag: 'fav-${image.index}',
            );
          },
        );
      },
    );
  }
}
