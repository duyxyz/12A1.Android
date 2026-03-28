import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FavoriteService {
  static const String _key = 'favorite_shas';
  static final ValueNotifier<Set<String>> favoritesNotifier =
      ValueNotifier<Set<String>>({});

  static Future<void> init() async {
    favoritesNotifier.value = await getFavorites();
  }

  static Future<Set<String>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    return list.toSet();
  }

  static Future<bool> isFavorite(String sha) async {
    return favoritesNotifier.value.contains(sha);
  }

  static Future<void> toggleFavorite(String sha) async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = (prefs.getStringList(_key) ?? []).toSet();

    if (favorites.contains(sha)) {
      favorites.remove(sha);
    } else {
      favorites.add(sha);
    }

    await prefs.setStringList(_key, favorites.toList());
    favoritesNotifier.value = favorites;
  }
}
