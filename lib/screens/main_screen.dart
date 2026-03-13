import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../main.dart';
import '../services/github_service.dart';
import '../services/supabase_service.dart';
import 'dart:async';
import '../utils/haptics.dart';
import '../utils/update_manager.dart';
import '../tabs/home_tab.dart';
import '../tabs/add_tab.dart';
import '../tabs/delete_tab.dart';
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
              debugPrint("Phát hiện thay đổi số lượng ảnh (${_images.length} -> ${data.length}), đang tải lại...");
              _loadData();
            } else {
              debugPrint("Số lượng ảnh không đổi (${data.length}), bỏ qua việc tải lại từ GitHub.");
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
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('🎉 Có bản cập nhật mới!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Phiên bản mới: ${updateData['tag_name']}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Nội dung thay đổi:',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: Text(
                  updateData['body'] ?? 'Cập nhật tính năng mới và sửa lỗi.',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
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
              DeleteTab(
                images: _images,
                isLoading: _isLoading,
                error: _error,
                onRefresh: _loadData,
              ),
              SettingsTab(isSelected: _selectedIndex == 3),
            ],
          ),
        ),
        bottomNavigationBar: Stack(
          children: [
            Theme(
              data: Theme.of(context).copyWith(
                splashFactory: NoSplash.splashFactory,
                highlightColor: Colors.transparent,
                splashColor: Colors.transparent,
                hoverColor: Colors.transparent,
                navigationBarTheme: NavigationBarThemeData(
                  labelTextStyle: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      );
                    }
                    return const TextStyle(fontSize: 11);
                  }),
                  iconTheme: WidgetStateProperty.resolveWith((states) {
                    return const IconThemeData(size: 25);
                  }),
                ),
              ),
              child: NavigationBar(
                height: 52,
                indicatorColor: Colors.transparent,
                selectedIndex: _selectedIndex,
                onDestinationSelected: (int index) {
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
                destinations: const <NavigationDestination>[
                  NavigationDestination(
                    selectedIcon: Icon(Icons.home),
                    icon: Icon(Icons.home_outlined),
                    label: 'Trang chủ',
                  ),
                  NavigationDestination(
                    selectedIcon: Icon(Icons.add_circle),
                    icon: Icon(Icons.add_circle_outline),
                    label: 'Thêm',
                  ),
                  NavigationDestination(
                    selectedIcon: Icon(Icons.delete),
                    icon: Icon(Icons.delete_outline),
                    label: 'Xóa',
                  ),
                  NavigationDestination(
                    selectedIcon: Icon(Icons.settings),
                    icon: Icon(Icons.settings_outlined),
                    label: 'Cài đặt',
                  ),
                ],
              ),
            ),
            // Lớp phủ trong suốt để bắt sự kiện Long Press vào nút Trang chủ
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: MediaQuery.of(context).size.width / 4,
              child: InkWell(
                onLongPress: _showRefreshDialog,
                onTap: () {
                  AppHaptics.lightImpact();
                  // Giữ nguyên logic tap của NavigationBar
                  if (_selectedIndex != 0) {
                    setState(() => _selectedIndex = 0);
                  } else {
                    if (_homeScrollController.hasClients) {
                      _homeScrollController.animateTo(
                        0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    }
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
