import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../main.dart';
import '../services/favorite_service.dart';
import '../widgets/image_grid_item.dart';

class FavoritesTab extends StatefulWidget {
  final List<Map<String, dynamic>> allImages;
  final bool isLoading;

  const FavoritesTab({
    super.key,
    required this.allImages,
    required this.isLoading,
  });

  @override
  State<FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends State<FavoritesTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return ValueListenableBuilder<Set<String>>(
      valueListenable: FavoriteService.favoritesNotifier,
      builder: (context, favoriteShas, _) {
        final filtered = widget.allImages
            .where((img) => favoriteShas.contains(img['sha']))
            .toList();

        final seen = <String>{};
        final favoriteImages = <Map<String, dynamic>>[];
        for (final img in filtered) {
          final sha = img['sha']?.toString();
          if (sha == null || seen.contains(sha)) continue;
          favoriteImages.add(img);
          seen.add(sha);
        }

        if (favoriteImages.isEmpty && !widget.isLoading) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.favorite_border_rounded,
                  size: 64,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withOpacity(0.5),
                ),
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

        return ValueListenableBuilder<int>(
          valueListenable: MyApp.gridColumnsNotifier,
          builder: (context, gridCols, _) {
            return MasonryGridView.count(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(4.0),
              crossAxisCount: gridCols,
              mainAxisSpacing: 4.0,
              crossAxisSpacing: 4.0,
              itemCount: favoriteImages.length,
              itemBuilder: (context, index) {
                final image = favoriteImages[index];
                final imageUrl = image['download_url'];
                final aspectRatio = image['aspect_ratio'] as double;
                return ImageGridItem(
                  imageUrl: imageUrl,
                  aspectRatio: aspectRatio,
                  imageMap: image,
                  heroTag: 'fav-${image['index']}',
                );
              },
            );
          },
        );
      },
    );
  }
}
