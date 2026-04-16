import 'dart:async';
import 'package:flutter/material.dart';
import '../main.dart';
import '../tabs/add_tab.dart';
import '../tabs/favorites_tab.dart';
import '../tabs/home_tab.dart';
import '../tabs/settings_tab.dart';
import '../utils/update_manager.dart';
import '../logic/viewmodels/home_view_model.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../widgets/update_bottom_sheet.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late ScrollController _nestedScrollController;
  final GlobalKey<HomeTabState> _homeTabKey = GlobalKey<HomeTabState>();
  final GlobalKey<FavoritesTabState> _favoritesTabKey =
      GlobalKey<FavoritesTabState>();
  final GlobalKey<AddTabState> _addTabKey = GlobalKey<AddTabState>();
  final GlobalKey<SettingsTabState> _settingsTabKey =
      GlobalKey<SettingsTabState>();

  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _nestedScrollController = ScrollController();
    _tabController.addListener(() {
      if (_currentIndex != _tabController.index) {
        setState(() {
          _currentIndex = _tabController.index;
        });
      }
    });

    // Initialize data through ViewModels
    AppDependencies.instance.homeViewModel.loadImages();
    _checkForUpdateSilent();
    cleanupUpdateFiles();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nestedScrollController.dispose();
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
    UpdateBottomSheet.show(context, release);
  }

  @override
  Widget build(BuildContext context) {
    final homeVM = AppDependencies.instance.homeViewModel;
    final appBarTextColor = Theme.of(context).colorScheme.primary;

    return PopScope(
      canPop: _tabController.index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_tabController.index != 0) {
          _tabController.animateTo(0);
        }
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: NestedScrollView(
            controller: _nestedScrollController,

            floatHeaderSlivers: true,
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                ListenableBuilder(
                  listenable: _tabController.animation!,
                  builder: (context, _) {
                    final animation = _tabController.animation;
                    double animValue = _tabController.index.toDouble();
                    if (animation != null) {
                      animValue = animation.value;
                    }

                    // factor = 1.0 at index 0, fades to 0.0 as we move to index 1, 2, 3
                    final homeFactor = (1.0 - animValue).clamp(0.0, 1.0);
                    final currentExpandedHeight = (homeFactor * 44.0) + 48.0;

                    return SliverOverlapAbsorber(
                      handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                        context,
                      ),
                      sliver: SliverPersistentHeader(
                        pinned: true,
                        delegate: _MainAppBarDelegate(
                          paddingTop: 0.0,
                          expandedHeight: currentExpandedHeight,
                          appBarTextColor: appBarTextColor,
                          homeVM: homeVM,
                          forceElevated: innerBoxIsScrolled,
                          tabBar: TabBar(
                            controller: _tabController,
                            indicatorSize: TabBarIndicatorSize.label,
                            labelColor: appBarTextColor,
                            unselectedLabelColor: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            indicatorColor: appBarTextColor,
                            dividerColor: Colors.transparent,
                            tabs: List.generate(4, (index) {
                              final animation = _tabController.animation!;
                              final icons = [
                                Symbols.home_rounded,
                                Symbols.favorite_rounded,
                                Symbols.add_circle_rounded,
                                Symbols.settings_rounded,
                              ];

                              return AnimatedBuilder(
                                animation: animation,
                                builder: (context, _) {
                                  double progress =
                                      (1.0 - (animation.value - index).abs())
                                          .clamp(0.0, 1.0);

                                  return Tab(
                                    icon: Icon(
                                      icons[index],
                                      size: 28,
                                      // Tăng mạnh Weight và Fill để thấy rõ sự khác biệt
                                      fill: progress > 0.5 ? 1.0 : 0.0,
                                      weight: 400 + (300 * progress),
                                      grade: progress > 0.5 ? 0.25 : 0.0,
                                    ),
                                  );
                                },
                              );
                            }),
                            onTap: (index) {
                              if (index == _currentIndex) {
                                if (_nestedScrollController.hasClients) {
                                  _nestedScrollController.animateTo(
                                    0,
                                    duration: const Duration(milliseconds: 500),
                                    curve: Curves.easeOutQuart,
                                  );
                                }
                                switch (index) {
                                  case 0:
                                    _homeTabKey.currentState?.scrollToTop();
                                    break;
                                  case 1:
                                    _favoritesTabKey.currentState
                                        ?.scrollToTop();
                                    break;
                                  case 2:
                                    _addTabKey.currentState?.scrollToTop();
                                    break;
                                  case 3:
                                    _settingsTabKey.currentState?.scrollToTop();
                                    break;
                                }
                              }
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ];
            },
            body: TabBarView(
              controller: _tabController,
              children: [
                HomeTab(key: _homeTabKey, viewModel: homeVM),
                FavoritesTab(key: _favoritesTabKey, viewModel: homeVM),
                AddTab(
                  key: _addTabKey,
                  viewModel: homeVM,
                  onStateChanged: () => setState(() {}),
                ),
                SettingsTab(
                  key: _settingsTabKey,
                  isSelected: _tabController.index == 3,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MainAppBarDelegate extends SliverPersistentHeaderDelegate {
  final double paddingTop;
  final double expandedHeight;
  final Color appBarTextColor;
  final HomeViewModel homeVM;
  final bool forceElevated;
  final Widget tabBar;

  _MainAppBarDelegate({
    required this.paddingTop,
    required this.expandedHeight,
    required this.appBarTextColor,
    required this.homeVM,
    required this.forceElevated,
    required this.tabBar,
  });

  @override
  double get maxExtent => paddingTop + expandedHeight;

  @override
  double get minExtent => paddingTop + 48.0;

  @override
  bool shouldRebuild(covariant _MainAppBarDelegate oldDelegate) {
    return expandedHeight != oldDelegate.expandedHeight ||
        paddingTop != oldDelegate.paddingTop ||
        appBarTextColor != oldDelegate.appBarTextColor ||
        homeVM != oldDelegate.homeVM ||
        forceElevated != oldDelegate.forceElevated;
  }

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final double currentHeight = maxExtent - shrinkOffset;
    final double currentFlexHeight = currentHeight - minExtent;
    final double factor = (currentFlexHeight / 44.0).clamp(0.0, 1.0);

    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: forceElevated || overlapsContent ? 2.0 : 0.0,
      surfaceTintColor: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: paddingTop - ((1.0 - factor) * 44.0),
            left: 0,
            right: 0,
            height: 44.0,
            child: Opacity(
              opacity: factor,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Gay Group',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                          color: appBarTextColor,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Center(
                        child: Text(
                          '${homeVM.images.length} ảnh',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                                color: appBarTextColor,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(bottom: 0, left: 0, right: 0, height: 48.0, child: tabBar),
        ],
      ),
    );
  }
}
