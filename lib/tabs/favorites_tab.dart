import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../main.dart';
import '../widgets/image_grid_item.dart';
import '../widgets/pulse_skeleton.dart';
import '../services/favorite_service.dart';

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
        final List<Map<String, dynamic>> filtered = widget.allImages
            .where((img) => favoriteShas.contains(img['sha']))
            .toList();

        // De-duplicate by SHA to be safe
        final Set<String> seen = {};
        final List<Map<String, dynamic>> favoriteImages = [];
        for (var img in filtered) {
          if (!seen.contains(img['sha'])) {
            favoriteImages.add(img);
            seen.add(img['sha']);
          }
        }

        if (favoriteImages.isEmpty && !widget.isLoading) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.favorite_border_rounded,
                  size: 64,
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'Chưa có ảnh yêu thích nào',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
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
                final imageUrl = favoriteImages[index]['download_url'];
                final aspectRatio =
                    favoriteImages[index]['aspect_ratio'] as double;
                return ImageGridItem(
                  imageUrl: imageUrl,
                  aspectRatio: aspectRatio,
                  imageMap: favoriteImages[index],
                  heroTag: 'fav-${favoriteImages[index]['sha']}',
                );
              },
            );
          },
        );
      },
    );
  }
}
