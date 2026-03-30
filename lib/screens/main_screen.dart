import 'dart:async';
import 'package:flutter/material.dart';
import '../main.dart';
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
  final ScrollController _homeScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Initialize data through ViewModels
    AppDependencies.instance.homeViewModel.loadImages();
    _checkForUpdateSilent();
    cleanupUpdateFiles();
  }

  @override
  void dispose() {
    _homeScrollController.dispose();
    super.dispose();
  }

  Future<void> _checkForUpdateSilent() async {
    final updateVM = AppDependencies.instance.updateViewModel;
    await updateVM.checkForUpdates();
    if (!mounted) return;

    if (updateVM.latestRelease != null) {
      _showUpdateDialog(context, updateVM.latestRelease!);
    }
  }

  void _showUpdateDialog(BuildContext context, dynamic release) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Cập nhật ứng dụng'),
        content: Text('Đã có phiên bản mới ${release.tagName}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Để sau'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              startUpdateProcess(context, release);
            },
            child: const Text('Cập nhật'),
          ),
        ],
      ),
    );
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
    final homeVM = AppDependencies.instance.homeViewModel;

    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: homeVM,
          builder: (context, _) {
            return IndexedStack(
              index: _selectedIndex,
              children: [
                HomeTab(
                  viewModel: homeVM,
                  scrollController: _homeScrollController,
                ),
                FavoritesTab(
                  allImages: homeVM.images,
                  isLoading: homeVM.isLoading,
                ),
                AddTab(
                  viewModel: homeVM,
                ),
                SettingsTab(isSelected: _selectedIndex == 3),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
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
            _buildNavItem(Icons.favorite_rounded, Icons.favorite_outline_rounded, 1),
            _buildNavItem(Icons.add_circle_rounded, Icons.add_circle_outline, 2),
            _buildNavItem(Icons.settings_rounded, Icons.settings_outlined, 3),
          ],
        ),
      ),
    );
  }
}
