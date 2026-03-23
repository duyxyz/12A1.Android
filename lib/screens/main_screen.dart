import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/github_service.dart';
import '../services/supabase_service.dart';
import 'dart:async';
import '../utils/haptics.dart';
import '../utils/update_manager.dart';
import '../tabs/home_tab.dart';
import '../tabs/add_tab.dart';
import '../tabs/settings_tab.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  List<Map<String, dynamic>> _images = [];
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
    _loadData();
    _setupRealtimeMetadata();
    _checkForUpdateSilent();
    cleanupUpdateFiles(); // Dọn dẹp file APK cũ
  }

  void _setupRealtimeMetadata() {
    _metadataSubscription = SupabaseService.metadataStream().listen((data) {
      if (data.isNotEmpty && mounted) {
        bool hasChanges = false;

        // 1. Cập nhật tỷ lệ ảnh cũ ngay tại chỗ nếu đã có dữ liệu GitHub
        if (_images.isNotEmpty) {
          final Map<int, double> newRatios = {
            for (var item in data)
              item['image_index'] as int: (item['aspect_ratio'] as num)
                  .toDouble(),
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

        // 2. Nếu có thay đổi về tỷ lệ, cập nhật UI ngay lập tức (không đợi GitHub)
        if (hasChanges) {
          setState(() {});
        }

        // 3. Chỉ tải lại từ GitHub nếu số lượng ảnh thay đổi hoặc sau khi hết debounce
        // Điều này xử lý trường hợp có ảnh mới được thêm vào hoặc bị xóa
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) {
            // Chỉ tải lại từ GitHub nếu số lượng ảnh thực sự thay đổi
            // (Xử lý trường hợp thêm/xóa ảnh)
            if (data.length != _images.length) {
              debugPrint(
                "Phát hiện thay đổi số lượng ảnh (${_images.length} -> ${data.length}), đang tải lại...",
              );
              _loadData();
            } else {
              debugPrint(
                "Số lượng ảnh không đổi (${data.length}), bỏ qua việc tải lại từ GitHub.",
              );
            }
          }
        });
      }
    });
  }

  Future<void> _checkForUpdateSilent() async {
    await Future.delayed(const Duration(seconds: 2));
    final result = await GithubService.checkUpdate();
    if (result['success'] == true) {
      final updateData = result['data'];
      final latestVersion = updateData['tag_name'].toString().replaceAll(
        'v',
        '',
      );
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;

      if (latestVersion != currentVersion && mounted) {
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
        content: Text(
          'Đã có phiên bản mới ${updateData['tag_name']}. Bạn muốn tải về và cài đặt ngay không?',
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
            child: const Text('Cập nhật'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = "";
    });
    try {
      final images = await GithubService.fetchImages();
      setState(() {
        _images = images;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _handleFullReload() {
    AppHaptics.heavyImpact();
    setState(() {
      _selectedIndex = 0; // Quay về trang chủ
      _images = []; // Xóa dữ liệu cũ để hiện loading
    });

    // Cuộn lên đầu trang
    if (_homeScrollController.hasClients) {
      _homeScrollController.jumpTo(0);
    }

    _loadData();
  }

  void _showRefreshDialog() {
    AppHaptics.mediumImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Làm mới trang ?'),
        content: const Text(
          'Bạn có muốn tải lại danh sách ảnh từ máy chủ không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _handleFullReload();
            },
            child: const Text('Đồng ý'),
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
              AddTab(
                images: _images,
                isLoading: _isLoading,
                error: _error,
                onRefresh: _loadData,
              ),
              SettingsTab(isSelected: _selectedIndex == 2),
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
            height: 48.0, // Bring it back down to the original 52 height
            color: Colors.transparent,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(Icons.home_rounded, Icons.home_outlined, 0),
                _buildNavItem(
                  Icons.add_circle_rounded,
                  Icons.add_circle_outline,
                  1,
                ),
                _buildNavItem(
                  Icons.settings_rounded,
                  Icons.settings_outlined,
                  2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
