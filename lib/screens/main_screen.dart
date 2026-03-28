import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/favorite_service.dart';
import '../services/github_service.dart';
import '../services/supabase_service.dart';
import '../tabs/add_tab.dart';
import '../tabs/favorites_tab.dart';
import '../tabs/home_tab.dart';
import '../tabs/settings_tab.dart';
import '../utils/haptics.dart';
import '../utils/update_manager.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  List<Map<String, dynamic>> _images = [];
  final GlobalKey<AddTabState> _addTabKey = GlobalKey<AddTabState>();
  bool _isLoading = true;
  String _error = "";
  final ScrollController _homeScrollController = ScrollController();
  StreamSubscription? _metadataSubscription;
  Timer? _debounceTimer;

  @override
  void dispose() {
    _homeScrollController.dispose();
    _metadataSubscription?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    FavoriteService.init();
    _loadData();
    _setupRealtimeMetadata();
    _checkForUpdateSilent();
    cleanupUpdateFiles();
  }

  void _setupRealtimeMetadata() {
    _metadataSubscription = SupabaseService.metadataStream().listen((data) {
      if (!mounted) return;

      var hasChanges = false;
      if (_images.isNotEmpty && data.isNotEmpty) {
        final newRatios = <int, double>{
          for (final item in data)
            item['image_index'] as int: (item['aspect_ratio'] as num).toDouble(),
        };

        for (var i = 0; i < _images.length; i++) {
          final idx = _images[i]['index'];
          if (idx != null && newRatios.containsKey(idx)) {
            if (_images[i]['aspect_ratio'] != newRatios[idx]) {
              _images[i]['aspect_ratio'] = newRatios[idx];
              hasChanges = true;
            }
          }
        }
      }

      if (hasChanges) {
        setState(() {});
      }

      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        if (data.length != _images.length || hasChanges) {
          debugPrint(
            "Phát hiện thay đổi dữ liệu hoặc số lượng ảnh (${_images.length} -> ${data.length}), đang tải lại...",
          );
          _loadData();
        } else {
          debugPrint(
            "Không có thay đổi quan trọng (${data.length} ảnh), bỏ qua việc tải lại từ GitHub.",
          );
        }
      });
    });
  }

  Future<void> _checkForUpdateSilent() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final result = await GithubService.checkUpdate();
    if (!mounted) return;

    if (result['success'] == true) {
      final updateData = result['data'];
      final latestVersion = updateData['tag_name'].toString().replaceAll('v', '');
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;

      final currentVersion = info.version;
      if (latestVersion != currentVersion) {
        _showUpdateDialog(context, updateData);
      }
    }
  }

  void _showUpdateDialog(
    BuildContext context,
    Map<String, dynamic> updateData,
  ) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Cập nhật ứng dụng'),
        content: Text('Đã có phiên bản mới ${updateData['tag_name']}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Để sau'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              startUpdateProcess(context, updateData);
            },
            child: const Text('Cập nhật'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = "";
    });

    try {
      final images = await GithubService.fetchImages();
      if (!mounted) return;
      setState(() {
        _images = images;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _handleFullReload() {
    AppHaptics.heavyImpact();
    setState(() {
      _selectedIndex = 0;
      _images = [];
    });

    if (_homeScrollController.hasClients) {
      _homeScrollController.jumpTo(0);
    }

    _loadData();
  }

  Widget _buildNavItem(IconData activeIcon, IconData icon, int index) {
    final isSelected = _selectedIndex == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_selectedIndex == 0 && index == 0) {
          if (_homeScrollController.hasClients) {
            _homeScrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        }
        AppHaptics.lightImpact();
        setState(() {
          _selectedIndex = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Icon(
          isSelected ? activeIcon : icon,
          size: 32,
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selectedIndex != 0) {
          setState(() {
            _selectedIndex = 0;
          });
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: IndexedStack(
            index: _selectedIndex,
            children: [
              HomeTab(
                images: _images,
                isLoading: _isLoading,
                error: _error,
                onRefresh: _loadData,
                scrollController: _homeScrollController,
              ),
              FavoritesTab(
                allImages: _images,
                isLoading: _isLoading,
              ),
              AddTab(
                key: _addTabKey,
                images: _images,
                isLoading: _isLoading,
                error: _error,
                onRefresh: _loadData,
              ),
              SettingsTab(isSelected: _selectedIndex == 3),
            ],
          ),
        ),
        extendBody: false,
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                width: 1.0,
              ),
            ),
          ),
          child: BottomAppBar(
            padding: EdgeInsets.zero,
            elevation: 0,
            height: 48.0,
            color: Colors.transparent,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(Icons.home_rounded, Icons.home_outlined, 0),
                _buildNavItem(
                  Icons.favorite_rounded,
                  Icons.favorite_outline_rounded,
                  1,
                ),
                _buildNavItem(
                  Icons.add_circle_rounded,
                  Icons.add_circle_outline,
                  2,
                ),
                _buildNavItem(
                  Icons.settings_rounded,
                  Icons.settings_outlined,
                  3,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
