import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:shimmer/shimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:local_auth/local_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load settings trước khi chạy app
  final prefs = await SharedPreferences.getInstance();
  
  final themeIndex = prefs.getInt('themeMode') ?? 0; // 0: system, 1: light, 2: dark
  final colorValue = prefs.getInt('themeColor') ?? Colors.blueAccent.value;
  final hapticsEnabled = prefs.getBool('hapticsEnabled') ?? true;
  final lockEnabled = prefs.getBool('lockEnabled') ?? false;
  final gridCols = prefs.getInt('gridColumns') ?? 2;
  
  MyApp.themeNotifier.value = ThemeMode.values[themeIndex];
  MyApp.themeColorNotifier.value = Color(colorValue);
  MyApp.hapticNotifier.value = hapticsEnabled;
  MyApp.lockNotifier.value = lockEnabled;
  MyApp.gridColumnsNotifier.value = gridCols;

  runApp(const MyApp());
}

class GithubService {
  // Ưu tiên lấy từ môi trường Build (GitHub Actions hoặc tham số --dart-define)
  // Để test local, bạn hãy chạy: flutter run --dart-define=GH_TOKEN=mã_token_của_bạn
  static String get token {
    const tokenFromEnv = String.fromEnvironment('GH_TOKEN');
    // SẠCH 100%: Không để token trong code. 
    // Khi chạy ở máy nhà (Offline), bạn hãy dùng lệnh: 
    // flutter run --dart-define=GH_TOKEN=ghp_mã_token_của_bạn
    return tokenFromEnv.isNotEmpty ? tokenFromEnv : '';
  }
  static const String owner = 'duyxyz';
  static const String repo = '12A1.Galary';
  static const String baseUrl =
      'https://api.github.com/repos/$owner/$repo/contents';

  // Lắng nghe trạng thái giới hạn API để cập nhật giao diện
  static final ValueNotifier<String> apiRemaining = ValueNotifier<String>(
    'Đang kiểm tra...',
  );

  static Map<String, String> get headers => {
    'Authorization': 'token $token',
    'Accept': 'application/vnd.github.v3+json',
  };

  static void _updateRateLimit(http.Response response) {
    if (response.headers.containsKey('x-ratelimit-remaining')) {
      apiRemaining.value =
          response.headers['x-ratelimit-remaining'] ?? 'Unknown';
    }
  }

  static Future<List<Map<String, dynamic>>> fetchImages() async {
    // 1. Tải images.json để lấy tỉ lệ w/h của các ảnh tạo khung (Skeleton)
    Map<int, double> aspectRatios = {};
    try {
      final jsonResponse = await http.get(
        Uri.parse(
          'https://raw.githubusercontent.com/duyxyz/12A1.Galary/main/images.json',
        ),
      );
      if (jsonResponse.statusCode == 200) {
        final List<dynamic> jsonData = json.decode(jsonResponse.body);
        for (var item in jsonData) {
          if (item is Map &&
              item['i'] != null &&
              item['w'] != null &&
              item['h'] != null) {
            aspectRatios[item['i']] = item['w'] / item['h'];
          }
        }
      }
    } catch (_) {
      // Bỏ qua lỗi nếu không lấy được images.json
    }

    // 2. Tải danh sách ảnh từ Github Repo
    final response = await http.get(Uri.parse(baseUrl), headers: headers);
    _updateRateLimit(response); // Cập nhật giới hạn Token

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      List<Map<String, dynamic>> images = [];
      for (var file in data) {
        if (file['name'].toString().endsWith('.webp')) {
          int index =
              int.tryParse(file['name'].toString().replaceAll('.webp', '')) ??
              0;
          images.add({
            'name': file['name'],
            'path': file['path'],
            'sha': file['sha'],
            'download_url': file['download_url'],
            'index': index,
            'aspect_ratio': aspectRatios[index] ?? 1.0,
          });
        }
      }
      images.sort(
        (a, b) => b['index'].compareTo(a['index']),
      );
      return images;
    } else {
      // Hiện chi tiết lỗi để debug (Rất quan trọng cho bản build Release)
      throw Exception('Lỗi API (${response.statusCode}): ${response.body}');
    }
  }

  static Future<void> uploadImage(String filename, Uint8List fileBytes) async {
    final base64Image = base64Encode(fileBytes);
    final response = await http.put(
      Uri.parse('$baseUrl/$filename'),
      headers: headers,
      body: jsonEncode({
        'message': 'Upload $filename (Android App)',
        'content': base64Image,
      }),
    );
    _updateRateLimit(response); // Cập nhật giới hạn Token

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Failed to upload image: ${response.body}');
    }
  }

  static Future<void> deleteImage(String path, String sha) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/$path'),
      headers: headers,
      body: jsonEncode({'message': 'Delete $path (Android App)', 'sha': sha}),
    );
    _updateRateLimit(response); // Cập nhật giới hạn Token

    if (response.statusCode != 200) {
      throw Exception('Failed to delete image: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>?> checkUpdate() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$owner/$repo/releases/latest'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (_) {}
    return null;
  }
}

class NoStretchScrollBehavior extends ScrollBehavior {
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    // Vô hiệu hóa hoàn toàn hiệu ứng lấp lánh (glow) hoặc co giãn (stretch) ở mép cuộn
    return child;
  }
}

class AppHaptics {
  static void lightImpact() {
    if (MyApp.hapticNotifier.value) HapticFeedback.lightImpact();
  }

  static void mediumImpact() {
    if (MyApp.hapticNotifier.value) HapticFeedback.mediumImpact();
  }

  static void heavyImpact() {
    if (MyApp.hapticNotifier.value) HapticFeedback.heavyImpact();
  }

  static void selectionClick() {
    if (MyApp.hapticNotifier.value) HapticFeedback.selectionClick();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Tạo một trình lắng nghe trạng thái Theme toàn cục cho App
  static final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(
    ThemeMode.system,
  );
  
  // Trình lắng nghe chọn màu chủ đạo
  static final ValueNotifier<Color> themeColorNotifier = ValueNotifier(
    Colors.blueAccent,
  );

  // Trình lắng nghe bật/tắt rung haptic
  static final ValueNotifier<bool> hapticNotifier = ValueNotifier(true);

  // Trình lắng nghe khóa ứng dụng (Biometric)
  static final ValueNotifier<bool> lockNotifier = ValueNotifier(false);

  // Trình lắng nghe số lượng cột lưới ảnh (1, 2, 3)
  static final ValueNotifier<int> gridColumnsNotifier = ValueNotifier(2);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, _) {
        return ValueListenableBuilder<Color>(
          valueListenable: themeColorNotifier,
          builder: (context, currentColor, _) {
            return MaterialApp(
              title: '12A1 THPT Đơn Dương',
              scrollBehavior: NoStretchScrollBehavior(), // Vô hiệu hóa hiệu ứng co giãn toàn app
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(seedColor: currentColor),
                useMaterial3: true,
              ),
              darkTheme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: currentColor,
                  brightness: Brightness.dark,
                ),
                useMaterial3: true,
              ),
              themeMode: currentMode,
              themeAnimationDuration: const Duration(milliseconds: 500),
              themeAnimationCurve: Curves.easeInOut,
              home: const AuthWrapper(child: MainScreen()),
            );
          },
        );
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  final Widget child;
  const AuthWrapper({super.key, required this.child});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  final LocalAuthentication auth = LocalAuthentication();
  bool _isAuthenticated = false;
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Nếu đang bật khóa, hiển thị màn hình khóa trước, bắt đầu xác thực
    if (MyApp.lockNotifier.value) {
      _checkAuth();
    } else {
      _isAuthenticated = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Khi app quay lại từ background, nếu đang bật khóa và chưa xác thực thì yêu cầu xác thực
    if (state == AppLifecycleState.resumed && MyApp.lockNotifier.value && !_isAuthenticated) {
      _checkAuth();
    }
    
    // Khi app xuống hẳn background (paused), khóa app lại ngay lập tức
    if (state == AppLifecycleState.paused && MyApp.lockNotifier.value) {
      setState(() => _isAuthenticated = false);
    }
  }

  Future<void> _checkAuth() async {
    if (_isAuthenticating || !MyApp.lockNotifier.value) return;
    
    setState(() => _isAuthenticating = true);

    try {
      final bool canAuthenticateWithBiometrics = await auth.canCheckBiometrics;
      final bool canAuthenticate = canAuthenticateWithBiometrics || await auth.isDeviceSupported();

      if (!canAuthenticate) {
        // Nếu máy không hỗ trợ khóa thì thôi (hoặc có thể dùng PIN máy)
        setState(() => _isAuthenticated = true);
        return;
      }

      final bool didAuthenticate = await auth.authenticate(
        localizedReason: 'Xác thực để mở khóa kho ảnh 12A1',
      );

      if (mounted) {
        setState(() {
          _isAuthenticated = didAuthenticate;
          _isAuthenticating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAuthenticated = true; // Cho phép vào nếu lỗi hệ thống xác thực
          _isAuthenticating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: MyApp.lockNotifier,
      builder: (context, isLockEnabled, _) {
        if (!isLockEnabled || _isAuthenticated) {
          return widget.child;
        }

        return Scaffold(
          body: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  Theme.of(context).colorScheme.surface,
                ],
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_person_outlined, size: 100, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 64),
                IconButton.filled(
                  onPressed: _checkAuth,
                  icon: const Icon(Icons.fingerprint, size: 32),
                  padding: const EdgeInsets.all(20),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

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
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    // Để cho app load xong data trước khi hiện popup update
    await Future.delayed(const Duration(seconds: 2));
    
    final updateData = await GithubService.checkUpdate();
    if (updateData == null || !mounted) return;

    // Lấy tag từ Github (ví dụ: v1.0.5 -> 1.0.5)
    final latestVersion = updateData['tag_name'].toString().replaceAll('v', '');
    
    // Lấy version thực tế của App (đã được GitHub Action tiêm vào lúc build)
    final info = await PackageInfo.fromPlatform();
    final currentVersion = info.version;

    // Nếu bản trên GitHub khác bản trên máy -> Hiện thông báo
    if (latestVersion != currentVersion) {
      _showUpdateDialog(updateData);
    }
  }

  void _showUpdateDialog(Map<String, dynamic> updateData) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
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
            onPressed: () => Navigator.pop(context),
            child: const Text('Để sau'),
          ),
          FilledButton(
            onPressed: () async {
              final url = Uri.parse(updateData['html_url']);
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
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
              AddTab(images: _images, onRefresh: _loadData),
              DeleteTab(images: _images, onRefresh: _loadData),
              SettingsTab(isSelected: _selectedIndex == 3),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
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
              label: 'Home',
            ),
            NavigationDestination(
              selectedIcon: Icon(Icons.add_circle),
              icon: Icon(Icons.add_circle_outline),
              label: 'Add',
            ),
            NavigationDestination(
              selectedIcon: Icon(Icons.delete),
              icon: Icon(Icons.delete_outline),
              label: 'Delete',
            ),
            NavigationDestination(
              selectedIcon: Icon(Icons.settings),
              icon: Icon(Icons.settings_outlined),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// 1. TRANG CHỦ (Home)
// ----------------------------------------------------------------------
class HomeTab extends StatefulWidget {
  final List<Map<String, dynamic>> images;
  final bool isLoading;
  final String error;
  final Future<void> Function() onRefresh;
  final ScrollController scrollController;

  const HomeTab({
    super.key,
    required this.images,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
    required this.scrollController,
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // Giữ nguyên danh sách tổng toàn trang

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.isLoading) {
      return Center(
        child: SizedBox(
          width: 200,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LinearProgressIndicator(borderRadius: BorderRadius.all(Radius.circular(4))),
            ],
          ),
        ),
      );
    }
    if (widget.error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Lỗi: ${widget.error}',
              style: const TextStyle(color: Colors.red),
            ),
            ElevatedButton(
              onPressed: widget.onRefresh,
              child: const Text('Thử lại'),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        ValueListenableBuilder<int>(
          valueListenable: MyApp.gridColumnsNotifier,
          builder: (context, gridCols, _) {
            return MasonryGridView.count(
              controller: widget.scrollController,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.all(4.0),
              crossAxisCount: gridCols,
              mainAxisSpacing: 4.0,
              crossAxisSpacing: 4.0,
              itemCount: widget.images.length,
              itemBuilder: (context, index) {
                final imageUrl = widget.images[index]['download_url'];
                final aspectRatio = widget.images[index]['aspect_ratio'] as double;
    
                return _ImageGridItem(imageUrl: imageUrl, aspectRatio: aspectRatio);
              },
            );
          },
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: () {
              AppHaptics.lightImpact();
              widget.onRefresh();
            },
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
            child: const Icon(Icons.cloud),
          ),
        ),
      ],
    );
  }
}

class _ImageGridItem extends StatefulWidget {
  final String imageUrl;
  final double aspectRatio;

  const _ImageGridItem({required this.imageUrl, required this.aspectRatio});

  @override
  State<_ImageGridItem> createState() => _ImageGridItemState();
}

class _ImageGridItemState extends State<_ImageGridItem>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // <-- Giữ nguyên state của Widget này, không bị hủy khi cuộn khỏi màn hình

  @override
  Widget build(BuildContext context) {
    super.build(
      context,
    ); // Cần gọi super khi dùng AutomaticKeepAliveClientMixin

    return InkWell(
      onTap: () async {
        AppHaptics.selectionClick();
        
        // Đo vị trí hiện tại của ảnh trên màn hình
        final RenderBox? box = context.findRenderObject() as RenderBox?;
        if (box != null) {
          final position = box.localToGlobal(Offset.zero);
          final bottom = position.dy + box.size.height;
          final screenHeight = MediaQuery.of(context).size.height;
          
          // Giả định thanh nav bar cao khoảng 80 (độ cao mặc định của NavigationBar)
          const navBarHeight = 80.0;
          final viewportBottom = screenHeight - navBarHeight;

          // Logic cuộn "vừa đủ":
          if (bottom > viewportBottom) {
            // Nếu khuất ở dưới -> cuộn lên vừa đủ để mép dưới ảnh chạm mép nav bar
            await Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 300),
              alignment: 1.0, 
              curve: Curves.easeInOut,
            );
          } else if (position.dy < 0) {
            // Nếu khuất ở trên -> cuộn xuống vừa đủ để mép trên ảnh chạm đỉnh màn hình
            await Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 300),
              alignment: 0.0,
              curve: Curves.easeInOut,
            );
          }
          // Nếu đã nằm gọn ở giữa thì không làm gì cả (không cuộn phí thời gian)
        }

        if (!mounted) return;

        Navigator.of(context).push(
          PageRouteBuilder(
            opaque: false,
            barrierColor: Colors.black,
            pageBuilder: (context, animation, secondaryAnimation) {
              return FullScreenImageViewer(
                imageUrl: widget.imageUrl,
                aspectRatio: widget.aspectRatio,
              );
            },
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      },
      child: ClipRRect(
        child: AspectRatio(
          aspectRatio: widget.aspectRatio,
          child: Hero(
            tag: widget.imageUrl,
            child: CachedNetworkImage(
              imageUrl: widget.imageUrl,
              fit: BoxFit.cover,
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              placeholder: (context, url) => Shimmer.fromColors(
                baseColor: Colors.grey.withValues(alpha: 0.3),
                highlightColor: Colors.grey.withValues(alpha: 0.1),
                child: Container(
                  color: Colors.white,
                ),
              ),
              errorWidget: (context, url, error) => const Icon(Icons.error),
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// 2. TRANG ADD (Tải ảnh lên)
// ----------------------------------------------------------------------
class AddTab extends StatefulWidget {
  final List<Map<String, dynamic>> images;
  final Future<void> Function() onRefresh;

  const AddTab({super.key, required this.images, required this.onRefresh});

  @override
  State<AddTab> createState() => _AddTabState();
}

class _AddTabState extends State<AddTab> {
  bool _isUploading = false;
  String _uploadStatus = "";
  final ImagePicker _picker = ImagePicker();
  List<XFile> _selectedImages = []; // Danh sách ảnh đã chọn

  // 1. Chọn nhiều ảnh và thêm vào danh sách
  Future<void> _pickImage() async {
    AppHaptics.lightImpact();
    try {
      final List<XFile> images = await _picker.pickMultiImage();
      if (images.isNotEmpty) {
        setState(() {
          _selectedImages.addAll(images);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi chọn ảnh: $e')),
        );
      }
    }
  }

  // 2. Nén và tải từng ảnh lên Github
  Future<void> _uploadImage() async {
    AppHaptics.lightImpact();
    if (_selectedImages.isEmpty) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Xác nhận Đăng Ảnh'),
          content: Text(
            'Bạn có chắc chắn muốn đăng ${_selectedImages.length} bức ảnh này lên Bộ Sưu Tập chung không?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Đồng ý'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() {
      _isUploading = true;
      _uploadStatus = "Bắt đầu tải lên...";
    });

    try {
      // Sao chép danh sách ảnh cũ để tính index chính xác
      List<Map<String, dynamic>> currentImages = List.from(widget.images);

      for (int i = 0; i < _selectedImages.length; i++) {
        final image = _selectedImages[i];
        setState(() {
          _uploadStatus = "Đang xử lý ${i + 1}/${_selectedImages.length}...";
        });

        // Nén & chuyển sang webp
        final Uint8List? compressedBytes =
            await FlutterImageCompress.compressWithFile(
              image.path,
              minWidth: 1920,
              minHeight: 1920,
              quality: 80,
              format: CompressFormat.webp,
            );

        if (compressedBytes == null) continue;

        // Tính tên file (tìm số trống nhỏ nhất)
        int nextIndex = 1;
        List<int> existingIndexes = currentImages
            .map<int>((img) => img['index'] as int)
            .toList()
          ..sort();

        for (int idx = 0; idx < existingIndexes.length; idx++) {
          if (existingIndexes[idx] == nextIndex) {
            nextIndex++;
          } else if (existingIndexes[idx] > nextIndex) {
            break;
          }
        }

        final filename = '$nextIndex.webp';
        await GithubService.uploadImage(filename, compressedBytes);

        // Giả lập cập nhật danh sách local để ảnh tiếp theo không trùng index
        currentImages.add({'index': nextIndex});
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã tải tất cả ảnh lên thành công!')),
        );
        setState(() {
          _selectedImages.clear();
        });
      }
      await widget.onRefresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi tải lên: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _removeImage(int index) {
    AppHaptics.lightImpact();
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  void _clearSelection() {
    AppHaptics.mediumImpact();
    setState(() {
      _selectedImages.clear();
    });
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _selectedImages.isNotEmpty && !_isUploading
          ? AppBar(
              title: Text('Đã chọn ${_selectedImages.length} ảnh'),
              actions: [
                IconButton(
                  onPressed: _clearSelection,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  tooltip: 'Xóa hết',
                ),
              ],
            )
          : null,
      body: _isUploading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_uploadStatus),
                ],
              ),
            )
          : _selectedImages.isNotEmpty
              ? Column(
                  children: [
                    Expanded(
                      child: GridView.builder(
                        physics: const ClampingScrollPhysics(),
                        padding: const EdgeInsets.all(8),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                        itemCount: _selectedImages.length + 1,
                        itemBuilder: (context, index) {
                          if (index == _selectedImages.length) {
                            return InkWell(
                              onTap: _pickImage,
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outlineVariant,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.add_a_photo_outlined),
                              ),
                            );
                          }
                          return Stack(
                            children: [
                              Positioned.fill(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(
                                    File(_selectedImages[index].path),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () => _removeImage(index),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _uploadImage,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Đăng tất cả ảnh'),
                        ),
                      ),
                    ),
                  ],
                )
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        iconSize: 120, // Tăng kích thước icon thêm ảnh
                        onPressed: _pickImage,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                      ),
                    ],
                  ),
                ),
    );
  }
}

// ----------------------------------------------------------------------
// 3. TRANG DELETE (Xóa ảnh)
// ----------------------------------------------------------------------
class DeleteTab extends StatefulWidget {
  final List<Map<String, dynamic>> images;
  final Future<void> Function() onRefresh;

  const DeleteTab({super.key, required this.images, required this.onRefresh});

  @override
  State<DeleteTab> createState() => _DeleteTabState();
}

class _DeleteTabState extends State<DeleteTab> {
  bool _isAuthenticated = false;
  bool _isDeleting = false;
  final Set<String> _selectedSha = {};

  void _authenticate() {
    setState(() {
      _isAuthenticated = true;
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedSha.isEmpty) return;
    
    AppHaptics.lightImpact();
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Xác nhận Xóa Ảnh'),
          content: Text('Bạn có chắc chắn muốn xóa vĩnh viễn ${_selectedSha.length} bức ảnh đã chọn khỏi Bộ Sưu Tập không? Hành động này không thể hoàn tác.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Xóa vĩnh viễn'),
            ),
          ],
        );
      },
    );
    
    if (confirm != true) return;

    setState(() => _isDeleting = true);

    try {
      int successCount = 0;
      for (String sha in _selectedSha) {
        // Tìm thông tin file theo sha
        final img = widget.images.firstWhere((e) => e['sha'] == sha);
        await GithubService.deleteImage(img['path'], sha);
        successCount++;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã xóa thành công $successCount ảnh')),
        );
      }
      setState(() {
        _selectedSha.clear();
      });
      await widget.onRefresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi xóa ảnh: $e')));
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthenticated) {
      return Center(
        child: InkWell(
          borderRadius: BorderRadius.circular(100),
          onTap: _authenticate,
          child: Container(
            padding: const EdgeInsets.all(48), // Tăng vùng bấm
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: const Icon(Icons.lock, size: 80), // Tăng kích thước icon khóa
          ),
        ),
      );
    }

    if (_isDeleting) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Đang xóa ảnh..."),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Đã chọn ${_selectedSha.length} ảnh để xóa',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: GridView.builder(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: widget.images.length,
            itemBuilder: (context, index) {
              final img = widget.images[index];
              final isSelected = _selectedSha.contains(img['sha']);

              return GestureDetector(
                onTap: () {
                  AppHaptics.selectionClick();
                  setState(() {
                    if (isSelected) {
                      _selectedSha.remove(img['sha']);
                    } else {
                      _selectedSha.add(img['sha']);
                    }
                  });
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: img['download_url'],
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Shimmer.fromColors(
                          baseColor: Colors.grey.withValues(alpha: 0.3),
                          highlightColor: Colors.grey.withValues(alpha: 0.1),
                          child: Container(color: Colors.white),
                        ),
                      ),
                    ),
                    if (isSelected)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red, width: 3),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.check_circle,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _isAuthenticated = false;
                      _selectedSha.clear();
                    });
                  },
                  child: const Text('Thoát'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton(
                  onPressed: _selectedSha.isEmpty ? null : _deleteSelected,
                  child: const Text('Xóa mục đã chọn'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------
// 4. TRANG SETTINGS (Cài đặt & Lịch sử)
// ----------------------------------------------------------------------
class SettingsTab extends StatefulWidget {
  final bool isSelected;
  const SettingsTab({super.key, this.isSelected = false});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  String _cacheSize = 'Đang tính...';

  @override
  void initState() {
    super.initState();
    // Mỗi khi vào tab Settings, ép cập nhật lại số Hz thật
    _updateHz();
    _calculateCacheSize();
  }

  @override
  void didUpdateWidget(covariant SettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Nếu tab Settings vừa được chọn (chuyển từ tab khác qua), tính lại cache
    if (widget.isSelected && !oldWidget.isSelected) {
      _calculateCacheSize();
    }
  }

  Future<void> _calculateCacheSize() async {
    try {
      int totalSize = 0;
      
      // Danh sách các thư mục cần quét (Chỉ Temp và Support mới là Cache)
      final dirs = [
        await getTemporaryDirectory(),
        await getApplicationSupportDirectory(),
      ];

      for (final dir in dirs) {
        if (dir.existsSync()) {
          try {
            await for (final file in dir.list(recursive: true, followLinks: false)) {
              if (file is File) {
                try {
                  totalSize += await file.length();
                } catch (_) {
                  // Bỏ qua nếu không truy cập được file
                }
              }
            }
          } catch (_) {
            // Bỏ qua nếu không liệt kê được thư mục
          }
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

  Future<void> _updateHz() async {
    // Không làm gì cả vì đã xóa chức năng liên quan tần số quét.
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const ClampingScrollPhysics(), // Tắt hiệu ứng kéo giãn cao su
      children: [
        const Divider(),
        ValueListenableBuilder<String>(
          valueListenable: GithubService.apiRemaining,
          builder: (context, remaining, _) {
            return Column(
              children: [
                ListTile(
                  title: const Text(
                    'Giới hạn API',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: Text(
                    '$remaining/5000',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    final version = snapshot.hasData ? snapshot.data!.version : '...';
                    return ListTile(
                      title: const Text('Phiên bản hiện tại'),
                      trailing: Text(
                        'v$version',
                        style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
        const Divider(),
        ValueListenableBuilder<bool>(
          valueListenable: MyApp.hapticNotifier,
          builder: (context, hapticsEnabled, _) {
            return SwitchListTile(
              title: const Text('Rung phản hồi'),
              subtitle: const Text('Phản hồi xúc giác khi chạm, vuốt'),
              secondary: const Icon(Icons.vibration),
              value: hapticsEnabled,
              onChanged: (bool value) async {
                MyApp.hapticNotifier.value = value;
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('hapticsEnabled', value);
                if (value) {
                  AppHaptics.lightImpact(); // Khỏi wrapper để user nhận biết ngay khi bật
                }
              },
            );
          },
        ),
        ValueListenableBuilder<bool>(
          valueListenable: MyApp.lockNotifier,
          builder: (context, lockEnabled, _) {
            return SwitchListTile(
              title: const Text('Khoá ứng dụng'),
              subtitle: const Text('Sử dụng vân tay hoặc khuôn mặt'),
              secondary: const Icon(Icons.security),
              value: lockEnabled,
              onChanged: (bool value) async {
                MyApp.lockNotifier.value = value;
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('lockEnabled', value);
                if (value) {
                  AppHaptics.lightImpact();
                }
              },
            );
          },
        ),
        const Divider(),
        ValueListenableBuilder<int>(
          valueListenable: MyApp.gridColumnsNotifier,
          builder: (context, gridCols, _) {
            return ListTile(
              title: const Text('Số lượng cột lưới ảnh'),
              trailing: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment<int>(value: 1, label: Text('1')),
                  ButtonSegment<int>(value: 2, label: Text('2')),
                  ButtonSegment<int>(value: 3, label: Text('3')),
                ],
                selected: {gridCols},
                onSelectionChanged: (Set<int> newSelection) async {
                  final newValue = newSelection.first;
                  MyApp.gridColumnsNotifier.value = newValue;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setInt('gridColumns', newValue);
                  AppHaptics.selectionClick();
                },
              ),
            );
          },
        ),
        const Divider(),
        ValueListenableBuilder<ThemeMode>(
          valueListenable: MyApp.themeNotifier,
          builder: (context, currentMode, _) {
            return ListTile(
              title: const Text('Chế độ sáng/tối'),
              trailing: SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto),
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.light,
                    icon: Icon(Icons.wb_sunny_rounded),
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.nightlight_round),
                  ),
                ],
                selected: {currentMode},
                onSelectionChanged: (Set<ThemeMode> newSelection) async {
                  final newValue = newSelection.first;
                  MyApp.themeNotifier.value = newValue;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setInt('themeMode', newValue.index);
                  AppHaptics.selectionClick();
                },
              ),
            );
          },
        ),
        const Divider(),
        ValueListenableBuilder<Color>(
          valueListenable: MyApp.themeColorNotifier,
          builder: (context, currentColor, _) {
            final List<Color> extendedColors = [
              Colors.red, Colors.redAccent, Colors.pink, Colors.pinkAccent,
              Colors.purple, Colors.deepPurple, Colors.indigo, Colors.blue,
              Colors.lightBlue, Colors.cyan, Colors.teal, Colors.green,
              Colors.lightGreen, Colors.lime, Colors.yellow, Colors.amber,
              Colors.orange, Colors.deepOrange, Colors.brown, Colors.grey,
              Colors.blueGrey, const Color(0xFF1E88E5), const Color(0xFF00897B), const Color(0xFFD81B60),
            ];

            return ListTile(
              title: const Text('Chọn màu tùy chỉnh'),
              subtitle: const Text('Nhấn để mở bảng màu'),
              trailing: Material(
                color: currentColor,
                elevation: 0,
                clipBehavior: Clip.antiAlias,
                shape: const CircleBorder(),
                child: const SizedBox(
                  width: 36,
                  height: 36,
                ),
              ),
              onTap: () {
                AppHaptics.selectionClick();
                showDialog(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: const Text('Chọn màu chủ đạo'),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const ClampingScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 6,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: extendedColors.length,
                          itemBuilder: (context, index) {
                            final color = extendedColors[index];
                            final isSelected = currentColor.value == color.value;
                            return GestureDetector(
                              onTap: () async {
                                AppHaptics.selectionClick();
                                MyApp.themeColorNotifier.value = color;
                                final prefs = await SharedPreferences.getInstance();
                                await prefs.setInt('themeColor', color.value);
                                if (context.mounted) Navigator.pop(context);
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: isSelected ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3) : null,
                                ),
                                child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
        const Divider(),
        ListTile(
          title: const Text('Xoá bộ nhớ đệm'),
          subtitle: Text('Dung lượng đang dùng: $_cacheSize'),
          leading: const Icon(Icons.delete_outline),
          onTap: () async {
            AppHaptics.mediumImpact();
            
            // 1. Xoá cache của flutter_cache_manager (chủ yếu là ảnh)
            await DefaultCacheManager().emptyCache();
            
            // 2. Xoá thủ công toàn bộ file trong các thư mục mà chúng ta quét dung lượng
            try {
              final dirs = [
                await getTemporaryDirectory(),
                await getApplicationSupportDirectory(),
              ];
              
              for (final dir in dirs) {
                if (dir.existsSync()) {
                  // listSync để lấy danh sách nhanh và xoá các file bên trong
                  final entities = dir.listSync(recursive: true, followLinks: false);
                  for (final entity in entities) {
                    if (entity is File) {
                      try {
                        await entity.delete();
                      } catch (_) {}
                    }
                  }
                }
              }
            } catch (_) {}

            // Đợi một chút để hệ thống file xử lý xong rồi mới tính lại dung lượng
            await Future.delayed(const Duration(milliseconds: 400));
            await _calculateCacheSize(); 
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Đã xoá sạch bộ nhớ đệm!'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ----------------------------------------------------------------------
// 5. WIDGET XEM ẢNH TOÀN MÀN HÌNH (Full Screen Viewer)
// ----------------------------------------------------------------------
class FullScreenImageViewer extends StatefulWidget {
  final String imageUrl;
  final double aspectRatio;

  const FullScreenImageViewer({
    super.key,
    required this.imageUrl,
    required this.aspectRatio,
  });

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer>
    with TickerProviderStateMixin {
  // ===== Zoom & Pan state =====
  double _scale = 1.0;
  double _baseScale = 1.0; // _scale tại thời điểm gesture bắt đầu
  Offset _offset = Offset.zero;
  Offset _baseOffset = Offset.zero; // _offset tại thời điểm gesture bắt đầu
  Offset _startFocalPoint = Offset.zero;

  // ===== Swipe-to-dismiss state =====
  bool _isDismissing = false;
  Offset _dismissOffset = Offset.zero;
  double _dismissScale = 1.0;

  // ===== Animation =====
  AnimationController? _resetAnim;

  @override
  void dispose() {
    _resetAnim?.dispose();
    super.dispose();
  }

  // ---------- GESTURE CALLBACKS ----------

  void _onScaleStart(ScaleStartDetails details) {
    _resetAnim?.stop();
    _baseScale = _scale;
    _baseOffset = _offset;
    _startFocalPoint = details.localFocalPoint;

    // Dismiss chỉ khi: 1 ngón tay + ảnh ở trạng thái gốc (chưa zoom / chưa pan)
    _isDismissing =
        details.pointerCount == 1 && _scale <= 1.01 && _offset.distance < 5;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      if (details.pointerCount >= 2) {
        // ===== ZOOM MODE =====
        // Nếu đang dismiss thì hủy, chuyển sang zoom
        if (_isDismissing) {
          _isDismissing = false;
          _dismissOffset = Offset.zero;
          _dismissScale = 1.0;
          // Cập nhật lại điểm gốc cho gesture zoom
          _baseScale = _scale;
          _baseOffset = _offset;
          _startFocalPoint = details.localFocalPoint;
          return;
        }

        final newScale = (_baseScale * details.scale).clamp(0.5, 5.0);
        final double k = newScale / _scale; // Tỉ lệ scale thay đổi lần này

        // Zoom quanh focal point: giữ điểm giữa 2 ngón tay đứng yên
        final screenSize = MediaQuery.of(context).size;
        final center = Offset(screenSize.width / 2, screenSize.height / 2);
        final focal = details.localFocalPoint;
        _offset = (focal - center) * (1 - k) + _offset * k;
        _scale = newScale;
      } else if (_isDismissing) {
        // ===== DISMISS MODE =====
        _dismissOffset += details.focalPointDelta;
        _dismissScale =
            (1.0 - (_dismissOffset.distance / 1500)).clamp(0.6, 1.0);
      } else if (_scale > 1.01) {
        // ===== PAN MODE (1 ngón tay khi đã zoom) =====
        _offset += details.focalPointDelta;
      }
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_isDismissing) {
      _isDismissing = false;
      if (_dismissOffset.distance > 100) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _dismissOffset = Offset.zero;
          _dismissScale = 1.0;
        });
      }
      return;
    }

    // Bounce back nếu scale < 1.0
    if (_scale < 1.0) {
      _animateReset(targetScale: 1.0, targetOffset: Offset.zero);
    } else if (_scale <= 1.05 && _offset.distance > 1) {
      // Gần 1.0 nhưng bị lệch → reset
      _animateReset(targetScale: 1.0, targetOffset: Offset.zero);
    }
  }

  // Double-tap: toggle zoom 2.5x ↔ 1.0x
  void _onDoubleTap() {
    if (_scale > 1.05) {
      _animateReset(targetScale: 1.0, targetOffset: Offset.zero);
    } else {
      _animateReset(targetScale: 2.5, targetOffset: Offset.zero);
    }
  }

  // ---------- DOWNLOAD & CONVERT ----------
  bool _isDownloading = false;

  Future<void> _downloadImage() async {
    if (_isDownloading) return;
    Navigator.pop(context); // Đóng popup menu trước khi bắt đầu tải

    setState(() {
      _isDownloading = true;
    });
    AppHaptics.mediumImpact();

    try {
      // 1. Tải dữ liệu ảnh từ URL
      final response = await http.get(Uri.parse(widget.imageUrl));
      if (response.statusCode != 200) {
        throw Exception("Server trả về lỗi: ${response.statusCode}");
      }
      
      final Uint8List imageBytes = response.bodyBytes;
      if (imageBytes.isEmpty) throw Exception("Dữ liệu ảnh trống");

      // 2. Chuyển đổi sang JPEG (vì máy có thể ko đọc đc WebP tải về trực tiếp)
      final Uint8List? jpegBytes = await FlutterImageCompress.compressWithList(
        imageBytes,
        format: CompressFormat.jpeg,
        quality: 95,
      );

      if (jpegBytes == null || jpegBytes.isEmpty) {
        throw Exception("Không thể chuyển đổi định dạng ảnh");
      }

      // 3. Kiểm tra quyền
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) throw Exception("Bạn chưa cấp quyền lưu ảnh cho ứng dụng");
      }

      // 4. Lưu vào máy
      final fileName = p.basenameWithoutExtension(widget.imageUrl);
      await Gal.putImageBytes(jpegBytes, name: fileName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã lưu vào bộ sưu tập'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint("Download error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: ${e.toString().replaceAll("Exception:", "").trim()}'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  // ---------- ANIMATION ----------
  
  void _animateReset({required double targetScale, required Offset targetOffset}) {
    final startScale = _scale;
    final startOffset = _offset;

    _resetAnim?.dispose();
    _resetAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    final curved = CurvedAnimation(
      parent: _resetAnim!,
      curve: Curves.easeOut,
    );

    curved.addListener(() {
      setState(() {
        final t = curved.value;
        _scale = startScale + (targetScale - startScale) * t;
        _offset = Offset.lerp(startOffset, targetOffset, t)!;
      });
    });

    _resetAnim!.forward();
  }

  // ---------- BUILD ----------

  @override
  Widget build(BuildContext context) {
    final double bgOpacity = _isDismissing
        ? (1.0 - (_dismissOffset.distance / 300)).clamp(0.0, 1.0)
        : 1.0;

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: bgOpacity),
      body: Stack(
        children: [
          GestureDetector(
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            onDoubleTap: _onDoubleTap,
            onLongPress: () {
              AppHaptics.mediumImpact();
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                builder: (context) => Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.download_rounded),
                        title: const Text('Tải xuống'),
                        onTap: _downloadImage,
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              );
            },
            behavior: HitTestBehavior.opaque,
            child: SizedBox.expand(
              child: Transform.translate(
                offset: _isDismissing ? _dismissOffset : Offset.zero,
                child: Transform.scale(
                  scale: _isDismissing ? _dismissScale : 1.0,
                  child: Center(
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..translate(_offset.dx, _offset.dy)
                        ..scale(_scale),
                      child: Hero(
                        tag: widget.imageUrl,
                        child: AspectRatio(
                          aspectRatio: widget.aspectRatio,
                          child: CachedNetworkImage(
                            imageUrl: widget.imageUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            placeholder: (context, url) => Center(
                              child: Shimmer.fromColors(
                                baseColor: Colors.grey.withValues(alpha: 0.3),
                                highlightColor: Colors.grey.withValues(alpha: 0.1),
                                child: Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) =>
                                const Icon(Icons.error, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Overlay Loading khi đang tải
          if (_isDownloading)
            Container(
              color: Colors.black45,
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        const Text('Đang lưu ảnh...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}


