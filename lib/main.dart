import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:shimmer/shimmer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class GithubService {
  static const String token = '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';
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
            // Lấy index để sắp xếp như bản web (vd: 1.webp -> 1)
            'index': index,
            // Áp dụng tỉ lệ thật, nếu ko có thì mặc định tỉ lệ vuông 1.0
            'aspect_ratio': aspectRatios[index] ?? 1.0,
          });
        }
      }
      images.sort(
        (a, b) => b['index'].compareTo(a['index']),
      ); // Giảm dần hoặc tăng dần tùy ý
      return images;
    } else {
      throw Exception('Failed to load images');
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
              home: const MainScreen(),
            );
          },
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
    return Scaffold(
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
            const SettingsTab(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          if (_selectedIndex == 0 && index == 0) {
            // Nếu đang ở Home mà lại bấm Home tiếp thì cuộn lên đầu trang
            if (_homeScrollController.hasClients) {
              _homeScrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          }
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

    if (widget.isLoading)
      return const Center(child: CircularProgressIndicator());
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

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      backgroundColor: Colors.black87,
      color: Colors.white,
      strokeWidth: 2.5,
      displacement: 60,
      edgeOffset: 10,
      child: MasonryGridView.count(
        controller: widget.scrollController,
        physics:
            const AlwaysScrollableScrollPhysics(), // Đệm vật lý gốc: Quăng mạnh kịch trần là đứng lại ngay
        padding: const EdgeInsets.all(4.0),
        crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
        mainAxisSpacing: 4.0,
        crossAxisSpacing: 4.0,
        itemCount: widget.images.length,
        itemBuilder: (context, index) {
          final imageUrl = widget.images[index]['download_url'];
          final aspectRatio = widget.images[index]['aspect_ratio'] as double;

          return _ImageGridItem(imageUrl: imageUrl, aspectRatio: aspectRatio);
        },
      ),
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
      onTap: () {
        // Sử dụng lại dạng Popup (Dialog) nhưng lấp đầy toàn màn hình bằng Dialog.fullscreen
        // Điều này đảm bảo trang chủ ở dưới KHÔNG HỀ thay đổi trạng thái và sinh ra lỗi chớp hình
        showDialog(
          context: context,
          // useSafeArea = false để vùng đen tràn sát viền khuyết màn hình
          useSafeArea: false,
          builder: (context) => Dialog.fullscreen(
            backgroundColor: Colors.black,
            child: Stack(
              children: [
                Center(
                  child: InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 5.0, // Cho phép zoom tới 5x
                    child: CachedNetworkImage(
                      imageUrl: widget.imageUrl,
                      fit: BoxFit.contain,
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
                // Nút Quay lại mô phỏng AppBar
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 8,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8.0),
        child: AspectRatio(
          aspectRatio: widget.aspectRatio,
          child: CachedNetworkImage(
            imageUrl: widget.imageUrl,
            fit: BoxFit.cover,
            // fadeInDuration tắt đi để không bị hiệu ứng chếp hình/mờ lại mỗi lần lướt hoặc quay lại
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
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickAndUploadImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      setState(() => _isUploading = true);

      // Nén & chuyển sang webp
      final Uint8List? compressedBytes =
          await FlutterImageCompress.compressWithFile(
            image.path,
            minWidth: 1920,
            minHeight: 1920,
            quality: 80,
            format: CompressFormat.webp,
          );

      if (compressedBytes == null) {
        throw Exception("Compression failed");
      }

      // Tính tên file (index cao nhất + 1)
      int nextIndex = 1;
      if (widget.images.isNotEmpty) {
        // Ảnh đang được sắp xếp giảm dần, nên phần tử đầu tiên là cao nhất
        // Thêm kiểm tra phòng ngừa
        final maxIndex = widget.images.reduce(
          (curr, next) => curr['index'] > next['index'] ? curr : next,
        )['index'];
        nextIndex = maxIndex + 1;
      }

      final filename = '$nextIndex.webp';

      await GithubService.uploadImage(filename, compressedBytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tải ảnh lên thành công!')),
        );
      }
      await widget.onRefresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isUploading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Đang xử lý và tải lên Github..."),
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_upload_outlined, size: 80),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _pickAndUploadImage,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text('Chọn ảnh từ thiết bị'),
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
          borderRadius: BorderRadius.circular(50),
          onTap: _authenticate,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: const Icon(Icons.lock, size: 48),
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
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  @override
  void initState() {
    super.initState();
    // Mỗi khi vào tab Settings, ép cập nhật lại số Hz thật
    _updateHz();
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
            return ListTile(
              title: Text(
                '$remaining / 5000',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            );
          },
        ),
        const Divider(),
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Giao diện hiển thị',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        ValueListenableBuilder<ThemeMode>(
          valueListenable: MyApp.themeNotifier,
          builder: (context, currentMode, _) {
            return RadioGroup<ThemeMode>(
              groupValue: currentMode,
              onChanged: (ThemeMode? value) {
                if (value != null) MyApp.themeNotifier.value = value;
              },
              child: Column(
                children: [
                  const RadioListTile<ThemeMode>(
                    title: Text('Theo hệ thống'),
                    secondary: Icon(Icons.brightness_auto),
                    value: ThemeMode.system,
                  ),
                  const RadioListTile<ThemeMode>(
                    title: Text('Chế độ sáng'),
                    secondary: Icon(Icons.wb_sunny_rounded),
                    value: ThemeMode.light,
                  ),
                  const RadioListTile<ThemeMode>(
                    title: Text('Chế độ tối'),
                    secondary: Icon(Icons.nightlight_round),
                    value: ThemeMode.dark,
                  ),
                ],
              ),
            );
          },
        ),
        const Divider(),
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Màu chủ đạo',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        ValueListenableBuilder<Color>(
          valueListenable: MyApp.themeColorNotifier,
          builder: (context, currentColor, _) {
            final List<Color> colors = [
              Colors.blueAccent,
              Colors.redAccent,
              Colors.green,
              Colors.orange,
              Colors.purple,
              Colors.pink,
              Colors.teal,
              Colors.amber,
              Colors.brown,
            ];

            return SizedBox(
              height: 60,
              child: ListView.separated(
                physics: const BouncingScrollPhysics(),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: colors.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final color = colors[index];
                  final isSelected = currentColor == color;
                  
                  return GestureDetector(
                    onTap: () {
                      MyApp.themeColorNotifier.value = color;
                    },
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(
                                color: Theme.of(context).colorScheme.onSurface,
                                width: 3,
                              )
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                  );
                },
              ),
            );
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
