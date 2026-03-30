import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../main.dart';
import '../data/models/gallery_image.dart';
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

    return ValueListenableBuilder<Set<String>>(
      valueListenable: FavoriteService.favoritesNotifier,
      builder: (context, favoriteShas, _) {
        final favoriteImages = allImages
            .where((img) => favoriteShas.contains(img.sha))
            .toList();

        if (favoriteImages.isEmpty && !isLoading) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 16),
                Text(
                  'Chưa có ảnh yêu thích nào',
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withOpacity(0.5),
                    fontSize: 16,
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
              key: const PageStorageKey<String>('favorites-grid'),
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(4.0),
              crossAxisCount: config.gridColumns,
              mainAxisSpacing: 4.0,
              crossAxisSpacing: 4.0,
              itemCount: favoriteImages.length,
              itemBuilder: (context, index) {
                final image = favoriteImages[index];
                return ImageGridItem(
                  key: ValueKey('fav-${image.sha}'),
                  image: image,
                );
              },
            );
          },
        );
      },
    );
  }
}
