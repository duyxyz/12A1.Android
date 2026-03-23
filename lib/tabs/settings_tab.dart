import 'dart:io';
import 'dart:math';
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
    return Theme(
      data: Theme.of(context).copyWith(
        listTileTheme: const ListTileThemeData(
          dense: true,
          horizontalTitleGap: 8,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
      ),
      child: ListView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        children: [
          _buildSectionCard(
            title: 'Giao diện & Hiển thị',
            children: [
              _buildThemeModeTile(context),
              const Divider(height: 1, indent: 48),
              _buildThemeColorTile(context),
              const Divider(height: 1, indent: 48),
              _buildGridColumnsTile(context),
            ],
          ),
          const SizedBox(height: 24),

          _buildSectionCard(
            title: 'Hệ thống & Trải nghiệm',
            children: [
              _buildSwitchTile(
                title: 'Phản hồi rung',
                icon: Icons.vibration_rounded,
                notifier: MyApp.hapticNotifier,
                onChanged: (v) async {
                  MyApp.hapticNotifier.value = v;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('hapticsEnabled', v);
                  if (v) AppHaptics.lightImpact();
                },
              ),
              const Divider(height: 1, indent: 48),
              _buildSwitchTile(
                title: 'Khóa ứng dụng',
                icon: Icons.lock_outline_rounded,
                notifier: MyApp.lockNotifier,
                onChanged: (v) async {
                  MyApp.lockNotifier.value = v;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('lockEnabled', v);
                  if (v) AppHaptics.lightImpact();
                },
              ),
            ],
          ),
          const SizedBox(height: 24),

          _buildSectionCard(
            title: 'Thông tin & Dọn dẹp',
            children: [
              _buildApiLimitTile(context),
              const Divider(height: 1, indent: 48),
              _buildVersionTile(context),
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
        ],
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

  Widget _buildSwitchTile({
    required String title,
    required IconData icon,
    required ValueNotifier<bool> notifier,
    required Function(bool) onChanged,
  }) {
    return ValueListenableBuilder<bool>(
      valueListenable: notifier,
      builder: (context, val, _) => SwitchListTile(
        title: Text(title, style: const TextStyle(fontSize: 14)),
        secondary: Icon(icon),
        value: val,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildThemeModeTile(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: MyApp.themeIndexNotifier,
      builder: (context, currentSettings, _) => ListTile(
        leading: const Icon(Icons.brightness_6_outlined),
        title: const Text('Chế độ màn hình', style: TextStyle(fontSize: 14)),
        trailing: DropdownButton<int>(
          value: currentSettings,
          underline: const SizedBox(),
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
            DropdownMenuItem(
              value: 3,
              child: Text('OLED', style: TextStyle(fontSize: 14)),
            ),
          ],
          onChanged: (index) async {
            if (index == null) return;
            MyApp.themeIndexNotifier.value = index;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt('themeMode', index);
            AppHaptics.selectionClick();
          },
        ),
      ),
    );
  }

  Widget _buildThemeColorTile(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: MyApp.themeColorNotifier,
      builder: (context, currentColor, _) => ListTile(
        leading: const Icon(Icons.palette_outlined),
        title: const Text('Màu sắc chủ đạo', style: TextStyle(fontSize: 14)),
        trailing: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.grey.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
        ),
        onTap: () => _showAreaColorPicker(context, currentColor),
      ),
    );
  }

  Widget _buildGridColumnsTile(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: MyApp.gridColumnsNotifier,
      builder: (context, currentSettings, _) => ListTile(
        leading: const Icon(Icons.grid_view_rounded),
        title: const Text('Số cột ảnh', style: TextStyle(fontSize: 14)),
        trailing: DropdownButton<int>(
          value: currentSettings,
          underline: const SizedBox(),
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
          onChanged: (cols) async {
            if (cols == null) return;
            MyApp.gridColumnsNotifier.value = cols;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt('gridColumns', cols);
            AppHaptics.selectionClick();
          },
        ),
      ),
    );
  }

  Widget _buildApiLimitTile(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: GithubService.apiRemaining,
      builder: (context, remaining, _) => ListTile(
        leading: const Icon(Icons.api_rounded),
        title: const Text('Giới hạn API', style: TextStyle(fontSize: 14)),
        subtitle: Text(
          'Còn lại: $remaining',
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildVersionTile(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) => ListTile(
        leading: const Icon(Icons.info_outline_rounded),
        title: const Text('Phiên bản', style: TextStyle(fontSize: 14)),
        subtitle: Text(
          'v${snapshot.data?.version ?? "..."} ',
          style: const TextStyle(fontSize: 12),
        ),
        onTap: () async {
          if (snapshot.hasData) {
            _manualUpdateCheck(context, snapshot.data!.version);
          }
        },
      ),
    );
  }

  Widget _buildCacheTile(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.cleaning_services_rounded),
      title: const Text('Xóa bộ nhớ đệm', style: TextStyle(fontSize: 14)),
      subtitle: Text(
        'Dung lượng: $_cacheSize',
        style: const TextStyle(fontSize: 12),
      ),
      onTap: () async {
        AppHaptics.mediumImpact();
        await DefaultCacheManager().emptyCache();
        final dirs = [
          await getTemporaryDirectory(),
          await getApplicationSupportDirectory(),
        ];
        for (final dir in dirs) {
          if (dir.existsSync()) {
            for (final entity in dir.listSync(recursive: true)) {
              if (entity is File) {
                try {
                  await entity.delete();
                } catch (_) {}
              }
            }
          }
        }
        if (mounted) {
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
    AppHaptics.lightImpact();
    final now = DateTime.now();
    if (_lastTapTime == null ||
        now.difference(_lastTapTime!) > const Duration(milliseconds: 500)) {
      _syncTapCount = 1;
    } else {
      _syncTapCount++;
    }
    _lastTapTime = now;
    if (_syncTapCount < 5) {
      if (_syncTapCount >= 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chạm thêm ${5 - _syncTapCount} lần nữa để đồng bộ'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
      return;
    }

    _syncTapCount = 0;
    AppHaptics.mediumImpact();
    final bool? confirmSync = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận đồng bộ?'),
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

    if (confirmSync != true || !SupabaseService.isInitialized) return;

    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
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

  void _showAreaColorPicker(BuildContext context, Color initialColor) {
    HSVColor hsv = HSVColor.fromColor(initialColor);
    double hue = hsv.hue;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Chọn màu chủ đạo'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Chạm vào vòng tròn để chọn tông màu',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 20),
                // --- Simple Color Wheel ---
                SizedBox(
                  width: 200,
                  height: 200,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // The Wheel (Hue circle)
                      CustomPaint(
                        size: const Size(200, 200),
                        painter: ColorWheelPainter(),
                      ),
                      // Gesture Overlay
                      GestureDetector(
                        onPanUpdate: (details) {
                          final RenderBox box =
                              context.findRenderObject() as RenderBox;
                          final Offset localOffset = details.localPosition;
                          final double centerX = 100;
                          final double centerY = 100;
                          final double dx = localOffset.dx - centerX;
                          final double dy = localOffset.dy - centerY;
                          double angle = atan2(dy, dx) * (180 / pi);
                          angle = (angle + 90) % 360; // Correction
                          if (angle < 0) angle += 360;
                          setDialogState(() => hue = angle);
                        },
                        onTapDown: (details) {
                          final Offset localOffset = details.localPosition;
                          final double centerX = 100;
                          final double centerY = 100;
                          final double dx = localOffset.dx - centerX;
                          final double dy = localOffset.dy - centerY;
                          double angle = atan2(dy, dx) * (180 / pi);
                          angle = (angle + 90) % 360; // Correction
                          if (angle < 0) angle += 360;
                          setDialogState(() => hue = angle);
                        },
                        child: Container(
                          width: 200,
                          height: 200,
                          decoration: const BoxDecoration(
                            color: Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      // Selector Indicator
                      IgnorePointer(
                        child: Transform.rotate(
                          angle: (hue - 90) * (pi / 180),
                          child: Stack(
                            children: [
                              // logic marker
                              Align(
                                alignment: Alignment.centerRight,
                                child: Container(
                                  margin: const EdgeInsets.only(right: 5),
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                    border: Border.all(
                                      color: Colors.black26,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Center Preview
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ColorScheme.fromSeed(
                            seedColor: HSVColor.fromAHSV(
                              1.0,
                              hue,
                              0.8,
                              0.9,
                            ).toColor(),
                            brightness: Theme.of(context).brightness,
                          ).primary,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(color: Colors.black12, blurRadius: 8),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Current selection hint
                Text(
                  'Màu đang chọn: #${HSVColor.fromAHSV(1.0, hue, 0.8, 0.9).toColor().value.toRadixString(16).substring(2).toUpperCase()}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: () async {
                  final finalColor = HSVColor.fromAHSV(
                    1.0,
                    hue,
                    0.8,
                    0.9,
                  ).toColor();
                  MyApp.themeColorNotifier.value = finalColor;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setInt('themeColor', finalColor.value);
                  if (context.mounted) Navigator.pop(context);
                  AppHaptics.mediumImpact();
                },
                child: const Text('Lưu màu'),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Custom Painter for the Color Wheel
class ColorWheelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const segments = 360;
    final sweepAngle = (2 * pi) / segments;

    for (int i = 0; i < segments; i++) {
      final paint = Paint()
        ..color = HSVColor.fromAHSV(1.0, i.toDouble(), 0.8, 0.9).toColor()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 40; // Thick enough to be easy to tap

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 20),
        (i - 90) * (pi / 180), // Offset by -90 to match atan2 behavior
        sweepAngle + 0.02,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
