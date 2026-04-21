import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../main.dart';
import '../utils/haptics.dart';
import '../utils/migrate_to_supabase.dart';
import '../widgets/expressive_loading_indicator.dart';
import '../widgets/update_bottom_sheet.dart';

class SettingsTab extends StatefulWidget {
  final bool isSelected;

  const SettingsTab({super.key, required this.isSelected});

  @override
  State<SettingsTab> createState() => SettingsTabState();
}

class SettingsTabState extends State<SettingsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  void scrollToTop() {
    if (!mounted) return;
    PrimaryScrollController.of(context).animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutQuart,
    );
  }

  String _cacheSize = 'Đang tính...';
  int _syncTapCount = 0;
  DateTime? _lastTapTime;
  @override
  void initState() {
    super.initState();
    _calculateCacheSize();
  }

  @override
  void didUpdateWidget(covariant SettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected && !oldWidget.isSelected) {
      _calculateCacheSize();
    }
  }

  Future<void> _calculateCacheSize() async {
    try {
      int totalSize = 0;
      final dirs = [
        await getTemporaryDirectory(),
        await getApplicationSupportDirectory(),
      ];

      for (final dir in dirs) {
        if (dir.existsSync()) {
          try {
            await for (final file in dir.list(
              recursive: true,
              followLinks: false,
            )) {
              if (file is File) {
                try {
                  totalSize += await file.length();
                } catch (_) {}
              }
            }
          } catch (_) {}
        }
      }

      if (mounted) {
        setState(() {
          _cacheSize = '${(totalSize / (1024 * 1024)).toStringAsFixed(1)} MB';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cacheSize = '0.0 MB';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final config = AppDependencies.instance.configViewModel;

    return Theme(
      data: Theme.of(context).copyWith(
        listTileTheme: const ListTileThemeData(
          dense: true,
          horizontalTitleGap: 8,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
      ),
      child: ListenableBuilder(
        listenable: config,
        builder: (context, _) => CustomScrollView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildSectionCard(
                    title: 'Giao diện & Hiển thị',
                    children: [
                      _buildThemeModeTile(context, config),
                      const Divider(height: 1, indent: 48),
                      _buildGridColumnsTile(context, config),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildSectionCard(
                    title: 'Thông tin & Dọn dẹp',
                    children: [
                      ListTile(
                        leading: const Icon(Icons.token_outlined),
                        title: const Text(
                          'Giới hạn API',
                          style: TextStyle(fontSize: 14),
                        ),
                        trailing: Text(
                          config.apiRemaining,
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const Divider(height: 1, indent: 48),
                      _buildCacheTile(context),
                      const Divider(height: 1, indent: 48),
                      ListTile(
                        leading: const Icon(Icons.aspect_ratio_rounded),
                        title: const Text('Đồng bộ kích thước ảnh'),
                        onTap: () => _handleSyncCommand(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildSectionCard(
                    title: 'Về ứng dụng',
                    children: [_buildVersionTile(context)],
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildThemeModeTile(BuildContext context, dynamic config) {
    return ListTile(
      leading: const Icon(Icons.brightness_6_outlined),
      title: const Text('Hiển Thị', style: TextStyle(fontSize: 14)),
      trailing: DropdownButton<int>(
        value: config.themeIndex,
        underline: const SizedBox(),
        alignment: Alignment.centerRight,
        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
        items: const [
          DropdownMenuItem(
            value: 0,
            child: Text('Tự động', style: TextStyle(fontSize: 14)),
          ),
          DropdownMenuItem(
            value: 1,
            child: Text('Sáng', style: TextStyle(fontSize: 14)),
          ),
          DropdownMenuItem(
            value: 2,
            child: Text('Tối', style: TextStyle(fontSize: 14)),
          ),
        ],
        onChanged: (index) {
          if (index != null) {
            config.setThemeIndex(index);
            AppHaptics.selectionClick();
          }
        },
      ),
    );
  }

  Widget _buildGridColumnsTile(BuildContext context, dynamic config) {
    return ListTile(
      leading: const Icon(Icons.grid_view_outlined),
      title: const Text('Số Cột', style: TextStyle(fontSize: 14)),
      trailing: DropdownButton<int>(
        value: config.gridColumns,
        underline: const SizedBox(),
        alignment: Alignment.centerRight,
        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
        items: const [
          DropdownMenuItem(
            value: 1,
            child: Text('1 Cột', style: TextStyle(fontSize: 14)),
          ),
          DropdownMenuItem(
            value: 2,
            child: Text('2 Cột', style: TextStyle(fontSize: 14)),
          ),
          DropdownMenuItem(
            value: 3,
            child: Text('3 Cột', style: TextStyle(fontSize: 14)),
          ),
        ],
        onChanged: (cols) {
          if (cols != null) {
            config.setGridColumns(cols);
            AppHaptics.selectionClick();
          }
        },
      ),
    );
  }

  Widget _buildVersionTile(BuildContext context) {
    final updateVM = AppDependencies.instance.updateViewModel;

    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) => ListTile(
        leading: const Icon(Icons.info_outline_rounded),
        title: const Text('Phiên bản', style: TextStyle(fontSize: 14)),
        trailing: Text(
          'v${snapshot.data?.version ?? "..."}',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        onTap: () async {
          if (snapshot.hasData) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Đang kiểm tra bản cập nhật mới...'),
                duration: Duration(seconds: 1),
              ),
            );
            await updateVM.checkForUpdates();
            if (updateVM.latestRelease != null) {
              if (context.mounted) {
                _showManualUpdateDialog(context, updateVM.latestRelease);
              }
            } else {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Bạn đang sử dụng phiên bản mới nhất!'),
                  ),
                );
              }
            }
          }
        },
      ),
    );
  }

  void _showManualUpdateDialog(BuildContext context, dynamic release) {
    UpdateBottomSheet.show(context, release);
  }

  Widget _buildCacheTile(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.cleaning_services_outlined),
      title: const Text('Xóa bộ nhớ đệm', style: TextStyle(fontSize: 14)),
      trailing: Text(
        _cacheSize,
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: () async {
        AppHaptics.mediumImpact();
        await DefaultCacheManager().emptyCache();
        final tempDir = await getTemporaryDirectory();
        if (tempDir.existsSync()) {
          for (final entity in tempDir.listSync(recursive: true)) {
            if (entity is File) {
              try {
                await entity.delete();
              } catch (_) {}
            }
          }
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã dọn dẹp bộ nhớ đệm thành công!')),
          );
        }
        await Future.delayed(const Duration(milliseconds: 400));
        await _calculateCacheSize();
      },
    );
  }

  Future<void> _handleSyncCommand(BuildContext context) async {
    // Legacy sync logic kept for compatibility
    AppHaptics.lightImpact();
    final now = DateTime.now();
    if (_lastTapTime == null ||
        now.difference(_lastTapTime!) > const Duration(milliseconds: 500)) {
      _syncTapCount = 1;
    } else {
      _syncTapCount++;
    }
    _lastTapTime = now;
    if (_syncTapCount < 10) return;

    _syncTapCount = 0;
    AppHaptics.mediumImpact();
    final bool? confirmSync = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận đồng bộ ?'),
        content: const Text(
          'Bắt đầu đồng bộ dữ liệu sửa lỗi từ hộp lưu trữ sang Mạng lưới ảnh?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Đồng ý'),
          ),
        ],
      ),
    );

    if (confirmSync != true) return;
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: ExpressiveLoadingIndicator(isContained: true)),
    );
    final result = await MigrationUtility.migrateFromGitHub();
    if (!context.mounted) return;
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Kết quả đồng bộ'),
        content: Text(result),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }
}
