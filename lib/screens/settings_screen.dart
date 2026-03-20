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

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _cacheSize = 'Đang tính...';
  int _syncTapCount = 0;
  DateTime? _lastTapTime;

  @override
  void initState() {
    super.initState();
    _calculateCacheSize();
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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cài đặt', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Hàng thông tin nhanh ──
              Row(
                children: [
                  Expanded(
                    child: _QuickInfoCard(
                      icon: Icons.api_rounded,
                      label: 'API',
                      child: ValueListenableBuilder<String>(
                        valueListenable: GithubService.apiRemaining,
                        builder: (_, remaining, __) => Text(
                          remaining,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final info = await PackageInfo.fromPlatform();
                        if (context.mounted) {
                          _manualUpdateCheck(context, info.version);
                        }
                      },
                      child: _QuickInfoCard(
                        icon: Icons.system_update_outlined,
                        label: 'Phiên bản',
                        child: FutureBuilder<PackageInfo>(
                          future: PackageInfo.fromPlatform(),
                          builder: (_, snapshot) => Text(
                            'v${snapshot.data?.version ?? "..."}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        AppHaptics.mediumImpact();
                        await DefaultCacheManager().emptyCache();
                        final dirs = [
                          await getTemporaryDirectory(),
                          await getApplicationSupportDirectory(),
                        ];
                        for (final dir in dirs) {
                          if (dir.existsSync()) {
                            for (final entity
                                in dir.listSync(recursive: true)) {
                              if (entity is File) {
                                try {
                                  await entity.delete();
                                } catch (_) {}
                              }
                            }
                          }
                        }
                        await Future.delayed(
                            const Duration(milliseconds: 400));
                        await _calculateCacheSize();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Đã dọn dẹp bộ nhớ đệm')),
                          );
                        }
                      },
                      child: _QuickInfoCard(
                        icon: Icons.cleaning_services_rounded,
                        label: 'Bộ nhớ',
                        child: Text(
                          _cacheSize,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
  
              const SizedBox(height: 20),
  
              // ── Section: Giao diện & Hiển thị ──
              const _SectionHeader(title: 'Giao diện'),
              const SizedBox(height: 6),
              _SettingsCard(
                children: [
                  // Chế độ màn hình
                  _DropdownSettingsTile<int>(
                    icon: Icons.brightness_6_rounded,
                    title: 'Chế độ màn hình',
                    valueNotifier: MyApp.themeIndexNotifier,
                    items: const [
                      PopupMenuItem(value: 0, child: Text('Tự động')),
                      PopupMenuItem(value: 1, child: Text('Sáng')),
                      PopupMenuItem(value: 2, child: Text('Tối')),
                      PopupMenuItem(value: 3, child: Text('OLED')),
                    ],
                    displayLabel: (index) {
                      switch (index) {
                        case 0: return 'Tự động';
                        case 1: return 'Sáng';
                        case 2: return 'Tối';
                        case 3: return 'OLED';
                        default: return 'Tự động';
                      }
                    },
                    onChanged: (index) async {
                      MyApp.themeIndexNotifier.value = index;
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setInt('themeMode', index);
                      AppHaptics.selectionClick();
                    },
                  ),
                  const _TileDivider(),
                  // Màu sắc chủ đạo
                  ValueListenableBuilder<Color>(
                    valueListenable: MyApp.themeColorNotifier,
                    builder: (context, currentColor, _) => ListTile(
                      leading: const Icon(Icons.palette_outlined),
                      title: const Text('Màu sắc chủ đạo'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 32,
                            height: 20,
                            decoration: BoxDecoration(
                              color: currentColor,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: colorScheme.outlineVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right_rounded,
                              size: 20, color: colorScheme.outline),
                        ],
                      ),
                      onTap: () =>
                          _showAreaColorPicker(context, currentColor),
                    ),
                  ),
                  const _TileDivider(),
                  // Bố cục lưới ảnh
                  _DropdownSettingsTile<int>(
                    icon: Icons.grid_view_rounded,
                    title: 'Bố cục lưới ảnh',
                    valueNotifier: MyApp.gridColumnsNotifier,
                    items: const [
                      PopupMenuItem(value: 1, child: Text('1 Cột')),
                      PopupMenuItem(value: 2, child: Text('2 Cột')),
                      PopupMenuItem(value: 3, child: Text('3 Cột')),
                    ],
                    displayLabel: (cols) => '$cols Cột',
                    onChanged: (cols) async {
                      MyApp.gridColumnsNotifier.value = cols;
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setInt('gridColumns', cols);
                      AppHaptics.selectionClick();
                    },
                  ),
                ],
              ),
  
              const SizedBox(height: 20),
  
              // ── Section: Hệ thống ──
              const _SectionHeader(title: 'Hệ thống'),
              const SizedBox(height: 6),
              _SettingsCard(
                children: [
                  // Haptics
                  ValueListenableBuilder<bool>(
                    valueListenable: MyApp.hapticNotifier,
                    builder: (context, val, _) => SwitchListTile(
                      secondary: Icon(
                        val ? Icons.vibration : Icons.vibration_outlined,
                        color: val ? colorScheme.primary : null,
                      ),
                      title: const Text('Phản hồi rung'),
                      value: val,
                      onChanged: (v) async {
                        MyApp.hapticNotifier.value = v;
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('hapticsEnabled', v);
                        if (v) AppHaptics.lightImpact();
                      },
                    ),
                  ),
                  const _TileDivider(),
                  // Lock
                  ValueListenableBuilder<bool>(
                    valueListenable: MyApp.lockNotifier,
                    builder: (context, val, _) => SwitchListTile(
                      secondary: Icon(
                        val ? Icons.lock : Icons.lock_open_rounded,
                        color: val ? colorScheme.primary : null,
                      ),
                      title: const Text('Khóa ứng dụng'),
                      value: val,
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
  
              const SizedBox(height: 20),
  
              // ── Section: Dữ liệu ──
              const _SectionHeader(title: 'Dữ liệu'),
              const SizedBox(height: 6),
              _SettingsCard(
                children: [
                  ListTile(
                    leading: const Icon(Icons.straighten_rounded),
                    title: const Text('Đồng bộ định dạng lưới'),
                    trailing: Icon(Icons.chevron_right_rounded,
                        size: 20, color: colorScheme.outline),
                    onTap: () async {
                      AppHaptics.lightImpact();
                      final now = DateTime.now();
                      if (_lastTapTime == null ||
                          now.difference(_lastTapTime!) >
                              const Duration(milliseconds: 500)) {
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
                          content: const Text(
                            'Bắt đầu đồng bộ kích thước từ GitHub sang Supabase?',
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
                      if (!SupabaseService.isInitialized) return;
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) =>
                            const Center(child: CircularProgressIndicator()),
                      );
                      final result =
                          await MigrationUtility.migrateFromGitHub();
                      Navigator.pop(context); // Close loading dialog
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
                    },
                  ),
                ],
              ),
  
              const SizedBox(height: 32),
            ],
          ),
        ),
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
                SizedBox(
                  width: 200,
                  height: 200,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(200, 200),
                        painter: ColorWheelPainter(),
                      ),
                      GestureDetector(
                        onPanUpdate: (details) {
                          final Offset localOffset = details.localPosition;
                          final double centerX = 100;
                          final double centerY = 100;
                          final double dx = localOffset.dx - centerX;
                          final double dy = localOffset.dy - centerY;
                          double angle = atan2(dy, dx) * (180 / pi);
                          angle = (angle + 90) % 360;
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
                          angle = (angle + 90) % 360;
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
                      IgnorePointer(
                        child: Transform.rotate(
                          angle: (hue - 90) * (pi / 180),
                          child: Stack(
                            children: [
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
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: HSVColor.fromAHSV(1.0, hue, 0.8, 0.9)
                              .toColor(),
                          border:
                              Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black12, blurRadius: 8),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
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
                  final finalColor =
                      HSVColor.fromAHSV(1.0, hue, 0.8, 0.9).toColor();
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

// ═══════════════════════════════════════════
//  Reusable Setting Widgets
// ═══════════════════════════════════════════

/// Section header label
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Card container for a group of settings
class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

/// Thin divider between tiles
class _TileDivider extends StatelessWidget {
  const _TileDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 56,
      endIndent: 16,
      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
    );
  }
}

/// Quick info card for the top row
class _QuickInfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;

  const _QuickInfoCard({
    required this.icon,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, size: 22, color: colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: colorScheme.outline),
            ),
            const SizedBox(height: 2),
            child,
          ],
        ),
      ),
    );
  }
}

/// Dropdown setting tile with PopupMenu
class _DropdownSettingsTile<T> extends StatelessWidget {
  final IconData icon;
  final String title;
  final ValueNotifier<T> valueNotifier;
  final List<PopupMenuItem<T>> items;
  final String Function(T) displayLabel;
  final Function(T) onChanged;

  const _DropdownSettingsTile({
    required this.icon,
    required this.title,
    required this.valueNotifier,
    required this.items,
    required this.displayLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ValueListenableBuilder<T>(
      valueListenable: valueNotifier,
      builder: (context, current, _) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            final RenderBox button = context.findRenderObject() as RenderBox;
            final RenderBox overlay =
                Overlay.of(context).context.findRenderObject() as RenderBox;
            final RelativeRect position = RelativeRect.fromRect(
              Rect.fromPoints(
                button.localToGlobal(
                  button.size.bottomRight(Offset.zero),
                  ancestor: overlay,
                ),
                button.localToGlobal(
                  button.size.bottomRight(Offset.zero),
                  ancestor: overlay,
                ),
              ),
              Offset.zero & overlay.size,
            );
            showMenu<T>(context: context, position: position, items: items)
                .then((val) {
              if (val != null) onChanged(val);
            });
          },
          child: Ink(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayLabel(current),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
              ],
            ),
          ),
        ),
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
        ..strokeWidth = 40;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 20),
        (i - 90) * (pi / 180),
        sweepAngle + 0.02,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
