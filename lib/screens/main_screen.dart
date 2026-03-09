import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../main.dart';
import '../services/github_service.dart';
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

  @override
  void dispose() {
    _homeScrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    _checkForUpdateSilent();
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
            child: const Text('Để sau'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _loadData();
            },
            child: const Text('Làm mới ngay'),
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
            NavigationBar(
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
