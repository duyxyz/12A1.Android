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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load settings trước khi chạy app
  final prefs = await SharedPreferences.getInstance();
  
  final themeIndex = prefs.getInt('themeMode') ?? 0; // 0: system, 1: light, 2: dark
  final colorValue = prefs.getInt('themeColor') ?? Colors.blueAccent.value;
  
  MyApp.themeNotifier.value = ThemeMode.values[themeIndex];
  MyApp.themeColorNotifier.value = Color(colorValue);

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

class NoStretchScrollBehavior extends ScrollBehavior {
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    // Vô hiệu hóa hoàn toàn hiệu ứng lấp lánh (glow) hoặc co giãn (stretch) ở mép cuộn
    return child;
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
            if (_homeScrollController.hasClients) {
              _homeScrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          }
          HapticFeedback.lightImpact();
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
        MasonryGridView.count(
          controller: widget.scrollController,
          physics: const ClampingScrollPhysics(),
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
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: () {
              HapticFeedback.lightImpact();
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
      onTap: () {
        HapticFeedback.selectionClick();
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
            flightShuttleBuilder: (
              flightContext,
              animation,
              flightDirection,
              fromHeroContext,
              toHeroContext,
            ) {
              return AspectRatio(
                aspectRatio: widget.aspectRatio,
                child: CachedNetworkImage(
                  imageUrl: widget.imageUrl,
                  fit: BoxFit.cover,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                ),
              );
            },
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
    HapticFeedback.lightImpact();
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
    HapticFeedback.lightImpact();
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
    HapticFeedback.lightImpact();
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  void _clearSelection() {
    HapticFeedback.mediumImpact();
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
    
    HapticFeedback.lightImpact();
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
                  HapticFeedback.selectionClick();
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
              onChanged: (ThemeMode? value) async {
                if (value != null) {
                  MyApp.themeNotifier.value = value;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setInt('themeMode', value.index);
                }
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
              trailing: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: currentColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Theme.of(context).colorScheme.outline),
                ),
              ),
              onTap: () {
                HapticFeedback.selectionClick();
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
                                HapticFeedback.selectionClick();
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
      body: GestureDetector(
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        onDoubleTap: _onDoubleTap,
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
                    flightShuttleBuilder: (
                      flightContext,
                      animation,
                      flightDirection,
                      fromHeroContext,
                      toHeroContext,
                    ) {
                      return AspectRatio(
                        aspectRatio: widget.aspectRatio,
                        child: CachedNetworkImage(
                          imageUrl: widget.imageUrl,
                          fit: BoxFit.cover,
                          fadeInDuration: Duration.zero,
                          fadeOutDuration: Duration.zero,
                        ),
                      );
                    },
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
    );
  }
}


