import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../main.dart';
import '../services/github_service.dart';
import '../utils/haptics.dart';
import '../utils/update_manager.dart';
import '../utils/migrate_to_supabase.dart';
import '../services/supabase_service.dart';

class SettingsTab extends StatefulWidget {
  final bool isSelected;
  const SettingsTab({super.key, this.isSelected = false});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
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

  Future<void> _manualUpdateCheck(
    BuildContext context,
    String currentVersion,
  ) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đang kiểm tra bản cập nhật mới...'),
        duration: Duration(seconds: 1),
      ),
    );

    final result = await GithubService.checkUpdate();

    if (!result['success']) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể kiểm tra: ${result['error']}')),
      );
      return;
    }

    final updateData = result['data'];
    final latestVersion = updateData['tag_name'].toString().replaceAll('v', '');

    if (!mounted) return;

    if (latestVersion != currentVersion) {
      _showUpdateDialog(context, updateData);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bạn đang sử dụng phiên bản mới nhất!')),
      );
    }
  }

  void _showUpdateDialog(
    BuildContext context,
    Map<String, dynamic> updateData,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('🎉 Có bản cập nhật mới!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Phiên bản mới: ${updateData['tag_name']}'),
            const SizedBox(height: 8),
            Text(updateData['body'] ?? 'Cập nhật tính năng mới và sửa lỗi.'),
          ],
        ),
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
            child: const Text('Cập nhật ngay'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Cụm Thông tin (Hàng 1) ---
            Row(
              children: [
                Expanded(
                  child: Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: ValueListenableBuilder<String>(
                      valueListenable: GithubService.apiRemaining,
                      builder: (context, remaining, _) => ListTile(
                        dense: true,
                        title: const Text('API Limit', style: TextStyle(fontSize: 12)),
                        subtitle: Text('$remaining/5000', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        leading: const Icon(Icons.api_rounded, size: 20),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: FutureBuilder<PackageInfo>(
                      future: PackageInfo.fromPlatform(),
                      builder: (context, snapshot) {
                        final version = snapshot.hasData ? snapshot.data!.version : '...';
                        return ListTile(
                          dense: true,
                          title: const Text('Phiên bản', style: TextStyle(fontSize: 12)),
                          subtitle: Text('v$version', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          leading: const Icon(Icons.info_outline_rounded, size: 20),
                          onTap: () => _manualUpdateCheck(context, version),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // --- Cụm Hệ thống (Hàng 2 - Grid) ---
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.2,
              children: [
                // Rung
                Card(
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: MyApp.hapticNotifier,
                    builder: (context, enabled, _) => InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final newValue = !enabled;
                        MyApp.hapticNotifier.value = newValue;
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('hapticsEnabled', newValue);
                        if (newValue) AppHaptics.lightImpact();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                        child: Row(
                          children: [
                            Icon(enabled ? Icons.vibration : Icons.vibration_outlined, 
                                 size: 20, color: enabled ? Theme.of(context).colorScheme.primary : null),
                            const SizedBox(width: 8),
                            const Expanded(child: Text('Rung', style: TextStyle(fontSize: 13))),
                            Switch(
                              value: enabled,
                              onChanged: (v) async {
                                MyApp.hapticNotifier.value = v;
                                final prefs = await SharedPreferences.getInstance();
                                await prefs.setBool('hapticsEnabled', v);
                              },
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Khóa
                Card(
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: MyApp.lockNotifier,
                    builder: (context, enabled, _) => InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final newValue = !enabled;
                        MyApp.lockNotifier.value = newValue;
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('lockEnabled', newValue);
                        if (newValue) AppHaptics.lightImpact();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                        child: Row(
                          children: [
                            Icon(enabled ? Icons.lock : Icons.lock_outline, 
                                 size: 20, color: enabled ? Theme.of(context).colorScheme.primary : null),
                            const SizedBox(width: 8),
                            const Expanded(child: Text('Khóa', style: TextStyle(fontSize: 13))),
                            Switch(
                              value: enabled,
                              onChanged: (v) async {
                                MyApp.lockNotifier.value = v;
                                final prefs = await SharedPreferences.getInstance();
                                await prefs.setBool('lockEnabled', v);
                              },
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Xoá Cache
                Card(
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      AppHaptics.mediumImpact();
                      await DefaultCacheManager().emptyCache();
                      // Clear files logic...
                      final dirs = [await getTemporaryDirectory(), await getApplicationSupportDirectory()];
                      for (final dir in dirs) {
                        if (dir.existsSync()) {
                          for (final entity in dir.listSync(recursive: true)) {
                            if (entity is File) try { await entity.delete(); } catch (_) {}
                          }
                        }
                      }
                      await Future.delayed(const Duration(milliseconds: 400));
                      await _calculateCacheSize();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.delete_sweep_outlined, size: 20),
                              SizedBox(width: 8),
                              Text('Xoá Cache', style: TextStyle(fontSize: 13)),
                            ],
                          ),
                          Text(_cacheSize, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
                        ],
                      ),
                    ),
                  ),
                ),
                // Màu sắc
                Card(
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: ValueListenableBuilder<Color>(
                    valueListenable: MyApp.themeColorNotifier,
                    builder: (context, currentColor, _) => InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        AppHaptics.selectionClick();
                        showDialog(
                          context: context,
                          builder: (context) {
                            HSVColor hsv = HSVColor.fromColor(currentColor);
                            double hue = hsv.hue;
                            double saturation = hsv.saturation;
                            double value = hsv.value;
                            return StatefulBuilder(
                              builder: (context, setDialogState) {
                                return AlertDialog(
                                  title: const Text('Chọn màu chủ đạo'),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        height: 80,
                                        margin: const EdgeInsets.only(bottom: 24),
                                        decoration: BoxDecoration(
                                          color: HSVColor.fromAHSV(1.0, hue, saturation, value).toColor(),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                                        ),
                                        child: const Center(
                                          child: Text('Màu đã chọn', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 4)]))),
                                      ),
                                      const Text('Tông màu (Hue)', style: TextStyle(fontSize: 12)),
                                      Slider(
                                        value: hue, max: 360, divisions: 360,
                                        activeColor: HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor(),
                                        onChanged: (v) => setDialogState(() => hue = v),
                                      ),
                                      const Text('Độ đậm (Saturation)', style: TextStyle(fontSize: 12)),
                                      Slider(
                                        value: saturation,
                                        activeColor: currentColor.withValues(alpha: saturation),
                                        onChanged: (v) => setDialogState(() => saturation = v),
                                      ),
                                      const Text('Độ sáng (Brightness)', style: TextStyle(fontSize: 12)),
                                      Slider(
                                        value: value,
                                        activeColor: Colors.grey.withValues(alpha: value),
                                        onChanged: (v) => setDialogState(() => value = v),
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
                                    FilledButton(
                                      onPressed: () async {
                                        final newColor = HSVColor.fromAHSV(1.0, hue, saturation, value).toColor();
                                        MyApp.themeColorNotifier.value = newColor;
                                        final prefs = await SharedPreferences.getInstance();
                                        await prefs.setInt('themeColor', newColor.value);
                                        if (context.mounted) Navigator.pop(context);
                                        AppHaptics.mediumImpact();
                                      },
                                      child: const Text('Lưu màu'),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        );
                      },
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.palette_outlined, size: 20),
                            const SizedBox(width: 8),
                            const Text('Màu sắc', style: TextStyle(fontSize: 13)),
                            const SizedBox(width: 8),
                            Container(width: 12, height: 12, decoration: BoxDecoration(color: currentColor, shape: BoxShape.circle)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // --- Giao diện (Hàng 3) ---
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: Column(
                  children: [
                    ValueListenableBuilder<ThemeMode>(
                      valueListenable: MyApp.themeNotifier,
                      builder: (context, currentMode, _) => ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        title: const Text('Chế độ màn hình', style: TextStyle(fontSize: 13)),
                        trailing: SegmentedButton<ThemeMode>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                              value: ThemeMode.system,
                              icon: Icon(Icons.brightness_auto),
                            ),
                            ButtonSegment(
                              value: ThemeMode.light,
                              icon: Icon(Icons.wb_sunny_rounded),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              icon: Icon(Icons.nightlight_round),
                            ),
                          ],
                          selected: {currentMode},
                          onSelectionChanged: (newSelection) async {
                            final newValue = newSelection.first;
                            MyApp.themeNotifier.value = newValue;
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setInt('themeMode', newValue.index);
                            AppHaptics.selectionClick();
                          },
                        ),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ValueListenableBuilder<int>(
                      valueListenable: MyApp.gridColumnsNotifier,
                      builder: (context, gridCols, _) => ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        title: const Text('Bố cục lưới ảnh', style: TextStyle(fontSize: 13)),
                        trailing: SegmentedButton<int>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: 1, label: Text('1')),
                            ButtonSegment(value: 2, label: Text('2')),
                            ButtonSegment(value: 3, label: Text('3')),
                          ],
                          selected: {gridCols},
                          onSelectionChanged: (newSelection) async {
                            final newValue = newSelection.first;
                            MyApp.gridColumnsNotifier.value = newValue;
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setInt('gridColumns', newValue);
                            AppHaptics.selectionClick();
                          },
                        ),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ValueListenableBuilder<String>(
                      valueListenable: GithubService.apiRemaining, // Dummy check, we just want standard look
                      builder: (context, _, __) => ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        title: const Text('Đồng bộ kích thước', style: TextStyle(fontSize: 13)),
                        leading: const Icon(Icons.sync_rounded, size: 20),
                        onTap: () async {
                          AppHaptics.lightImpact();
                          final now = DateTime.now();
                          if (_lastTapTime == null || now.difference(_lastTapTime!) > const Duration(milliseconds: 500)) {
                            _syncTapCount = 1;
                          } else {
                            _syncTapCount++;
                          }
                          _lastTapTime = now;
                          if (_syncTapCount < 5) return;
                          _syncTapCount = 0;
                          AppHaptics.mediumImpact();
                          final bool? confirmSync = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Xác nhận đồng bộ?'),
                              content: const Text('Bắt đầu đồng bộ kích thước từ GitHub sang Supabase?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
                                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Đồng ý')),
                              ],
                            ),
                          );
                          if (confirmSync != true) return;
                          if (!SupabaseService.isInitialized) return;
                          showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
                          final result = await MigrationUtility.migrateFromGitHub();
                          Navigator.pop(context);
                          showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Kết quả đồng bộ'), content: Text(result), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Đóng'))]));
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
