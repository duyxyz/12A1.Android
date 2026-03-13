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
            // --- Cụm Thông tin (Hàng 1 - 3 Ô bằng nhau) ---
            Row(
              children: [
                Expanded(
                  child: _buildInfoCard(
                    context,
                    title: 'API Limit',
                    icon: Icons.api_rounded,
                    content: ValueListenableBuilder<String>(
                      valueListenable: GithubService.apiRemaining,
                      builder: (context, remaining, _) => Text('$remaining/5k', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildInfoCard(
                    context,
                    title: 'Phiên bản',
                    icon: Icons.info_outline_rounded,
                    onTap: () async {
                      final info = await PackageInfo.fromPlatform();
                      if (context.mounted) _manualUpdateCheck(context, info.version);
                    },
                    content: FutureBuilder<PackageInfo>(
                      future: PackageInfo.fromPlatform(),
                      builder: (context, snapshot) => Text('v${snapshot.data?.version ?? "..."}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildInfoCard(
                    context,
                    title: 'Bộ nhớ',
                    icon: Icons.cleaning_services_rounded,
                    onTap: () async {
                      AppHaptics.mediumImpact();
                      await DefaultCacheManager().emptyCache();
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
                    content: Text(_cacheSize, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // --- Cụm Hệ thống (Hàng 2 - Grid 2 Ô) ---
            Row(
              children: [
                Expanded(
                  child: _buildSystemCard(
                    context,
                    title: 'Rung',
                    icon: MyApp.hapticNotifier.value ? Icons.vibration : Icons.vibration_outlined,
                    enabled: MyApp.hapticNotifier,
                    onChanged: (v) async {
                      MyApp.hapticNotifier.value = v;
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('hapticsEnabled', v);
                      if (v) AppHaptics.lightImpact();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSystemCard(
                    context,
                    title: 'Khóa',
                    icon: MyApp.lockNotifier.value ? Icons.lock : Icons.lock_outline,
                    enabled: MyApp.lockNotifier,
                    onChanged: (v) async {
                      MyApp.lockNotifier.value = v;
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('lockEnabled', v);
                      if (v) AppHaptics.lightImpact();
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // --- Màu sắc (Ô lẻ) ---
            Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: ValueListenableBuilder<Color>(
                valueListenable: MyApp.themeColorNotifier,
                builder: (context, currentColor, _) => InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _showAreaColorPicker(context, currentColor),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        const Icon(Icons.palette_outlined, size: 24),
                        const SizedBox(width: 12),
                        const Text('Màu sắc chủ đạo', style: TextStyle(fontWeight: FontWeight.w500)),
                        const Spacer(),
                        Container(
                          width: 40,
                          height: 24,
                          decoration: BoxDecoration(
                            color: currentColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white24),
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // --- Giao diện (Thành phần xổ xuống) ---
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Column(
                children: [
                  _buildDropdownTile<ThemeMode>(
                    context,
                    title: 'Chế độ màn hình',
                    icon: Icons.brightness_6_rounded,
                    value: MyApp.themeNotifier,
                    items: const [
                      PopupMenuItem(value: ThemeMode.system, child: Text('Tự động')),
                      PopupMenuItem(value: ThemeMode.light, child: Text('Sáng')),
                      PopupMenuItem(value: ThemeMode.dark, child: Text('Tối')),
                    ],
                    onChanged: (mode) async {
                      MyApp.themeNotifier.value = mode;
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setInt('themeMode', mode.index);
                      AppHaptics.selectionClick();
                    },
                    displayLabel: (mode) => mode == ThemeMode.system ? 'Tự động' : (mode == ThemeMode.light ? 'Sáng' : 'Tối'),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _buildDropdownTile<int>(
                    context,
                    title: 'Bố cục lưới ảnh',
                    icon: Icons.grid_view_rounded,
                    value: MyApp.gridColumnsNotifier,
                    items: const [
                       PopupMenuItem(value: 1, child: Text('1 Cột')),
                       PopupMenuItem(value: 2, child: Text('2 Cột')),
                       PopupMenuItem(value: 3, child: Text('3 Cột')),
                    ],
                    onChanged: (cols) async {
                      MyApp.gridColumnsNotifier.value = cols;
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setInt('gridColumns', cols);
                      AppHaptics.selectionClick();
                    },
                    displayLabel: (cols) => '$cols Cột',
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    title: const Text('Đồng bộ kích thước', style: TextStyle(fontSize: 14)),
                    leading: const Icon(Icons.sync_rounded),
                    trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Helper Widgets ---

  Widget _buildInfoCard(BuildContext context, {required String title, required IconData icon, required Widget content, VoidCallback? onTap}) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Column(
            children: [
              Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8)),
              const SizedBox(height: 6),
              Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 2),
              content,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSystemCard(BuildContext context, {required String title, required IconData icon, required ValueNotifier<bool> enabled, required Function(bool) onChanged}) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: ValueListenableBuilder<bool>(
        valueListenable: enabled,
        builder: (context, val, _) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 20, color: val ? Theme.of(context).colorScheme.primary : null),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
              Switch(
                value: val,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownTile<T>(BuildContext context, {required String title, required IconData icon, required ValueNotifier<T> value, required List<PopupMenuItem<T>> items, required Function(T) onChanged, required String Function(T) displayLabel}) {
    return ValueListenableBuilder<T>(
      valueListenable: value,
      builder: (context, current, _) => ListTile(
        title: Text(title, style: const TextStyle(fontSize: 14)),
        leading: Icon(icon),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(displayLabel(current), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
            ],
          ),
        ),
        onTap: () {
          final RenderBox button = context.findRenderObject() as RenderBox;
          final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
          final RelativeRect position = RelativeRect.fromRect(
            Rect.fromPoints(
              button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
              button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
            ),
            Offset.zero & overlay.size,
          );
          showMenu<T>(context: context, position: position, items: items).then((val) {
             if (val != null) onChanged(val);
          });
        },
      ),
    );
  }

  void _showAreaColorPicker(BuildContext context, Color initialColor) {
    HSVColor hsv = HSVColor.fromColor(initialColor);
    double hue = hsv.hue;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final currentColor = HSVColor.fromAHSV(1.0, hue, 0.8, 0.9).toColor();
          return AlertDialog(
            title: const Text('Chọn màu chủ đạo'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Tích vào vùng màu bạn thích', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 16),
                // Color Area (Map)
                SizedBox(
                  height: 200,
                  width: double.maxFinite,
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8, crossAxisSpacing: 4, mainAxisSpacing: 4),
                    itemCount: 64, // 8x8 grid of various hues
                    itemBuilder: (context, index) {
                      final itemHue = (index / 64) * 360;
                      final itemColor = HSVColor.fromAHSV(1.0, itemHue, 0.7, 0.9).toColor();
                      final isSelected = (hue - itemHue).abs() < (360 / 128);
                      return GestureDetector(
                        onTap: () => setDialogState(() => hue = itemHue),
                        child: Container(
                          decoration: BoxDecoration(
                            color: itemColor,
                            borderRadius: BorderRadius.circular(6),
                            border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
                            boxShadow: isSelected ? [BoxShadow(color: itemColor.withValues(alpha: 0.5), blurRadius: 8)] : null,
                          ),
                          child: isSelected ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                // Detailed Adjust Slider
                Row(
                  children: [
                    const Text('Tinh chỉnh', style: TextStyle(fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: hue,
                        max: 360,
                        onChanged: (v) => setDialogState(() => hue = v),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
              FilledButton(
                onPressed: () async {
                  final finalColor = HSVColor.fromAHSV(1.0, hue, 0.8, 0.9).toColor();
                  MyApp.themeColorNotifier.value = finalColor;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setInt('themeColor', finalColor.value);
                  if (context.mounted) Navigator.pop(context);
                  AppHaptics.mediumImpact();
                },
                child: const Text('Chọn màu này'),
              ),
            ],
          );
        },
      ),
    );
  }
}
