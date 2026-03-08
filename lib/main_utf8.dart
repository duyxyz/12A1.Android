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
  
  // Load settings trÆ°á»›c khi cháº¡y app
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

  // Láº¯ng nghe tráº¡ng thÃ¡i giá»›i háº¡n API Ä‘á»ƒ cáº­p nháº­t giao diá»‡n
  static final ValueNotifier<String> apiRemaining = ValueNotifier<String>(
    'Äang kiá»ƒm tra...',
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
    // 1. Táº£i images.json Ä‘á»ƒ láº¥y tá»‰ lá»‡ w/h cá»§a cÃ¡c áº£nh táº¡o khung (Skeleton)
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
      // Bá» qua lá»—i náº¿u khÃ´ng láº¥y Ä‘Æ°á»£c images.json
    }

    // 2. Táº£i danh sÃ¡ch áº£nh tá»« Github Repo
    final response = await http.get(Uri.parse(baseUrl), headers: headers);
    _updateRateLimit(response); // Cáº­p nháº­t giá»›i háº¡n Token

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
            // Láº¥y index Ä‘á»ƒ sáº¯p xáº¿p nhÆ° báº£n web (vd: 1.webp -> 1)
            'index': index,
            // Ãp dá»¥ng tá»‰ lá»‡ tháº­t, náº¿u ko cÃ³ thÃ¬ máº·c Ä‘á»‹nh tá»‰ lá»‡ vuÃ´ng 1.0
            'aspect_ratio': aspectRatios[index] ?? 1.0,
          });
        }
      }
      images.sort(
        (a, b) => b['index'].compareTo(a['index']),
      ); // Giáº£m dáº§n hoáº·c tÄƒng dáº§n tÃ¹y Ã½
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
    _updateRateLimit(response); // Cáº­p nháº­t giá»›i háº¡n Token

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
    _updateRateLimit(response); // Cáº­p nháº­t giá»›i háº¡n Token

    if (response.statusCode != 200) {
      throw Exception('Failed to delete image: ${response.body}');
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Táº¡o má»™t trÃ¬nh láº¯ng nghe tráº¡ng thÃ¡i Theme toÃ n cá»¥c cho App
  static final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(
    ThemeMode.system,
  );
  
  // TrÃ¬nh láº¯ng nghe chá»n mÃ u chá»§ Ä‘áº¡o
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
              title: '12A1 THPT ÄÆ¡n DÆ°Æ¡ng',
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
// 1. TRANG CHá»¦ (Home)
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
  bool get wantKeepAlive => true; // Giá»¯ nguyÃªn danh sÃ¡ch tá»•ng toÃ n trang

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
              'Lá»—i: ${widget.error}',
              style: const TextStyle(color: Colors.red),
            ),
            ElevatedButton(
              onPressed: widget.onRefresh,
              child: const Text('Thá»­ láº¡i'),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        MasonryGridView.count(
          controller: widget.scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
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
            child: const Icon(Icons.refresh),
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
  bool get wantKeepAlive => true; // <-- Giá»¯ nguyÃªn state cá»§a Widget nÃ y, khÃ´ng bá»‹ há»§y khi cuá»™n khá»i mÃ n hÃ¬nh

  @override
  Widget build(BuildContext context) {
    super.build(
      context,
    ); // Cáº§n gá»i super khi dÃ¹ng AutomaticKeepAliveClientMixin

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
              return AnimatedBuilder(
                animation: animation,
                builder: (context, child) {
                  return CachedNetworkImage(
                    imageUrl: widget.imageUrl,
                    fit: BoxFit.cover,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                  );
                },
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
// 2. TRANG ADD (Táº£i áº£nh lÃªn)
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
  List<XFile> _selectedImages = []; // Danh sÃ¡ch áº£nh Ä‘Ã£ chá»n

  // 1. Chá»n nhiá»u áº£nh vÃ  thÃªm vÃ o danh sÃ¡ch
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
          SnackBar(content: Text('Lá»—i chá»n áº£nh: $e')),
        );
      }
    }
  }

  // 2. NÃ©n vÃ  táº£i tá»«ng áº£nh lÃªn Github
  Future<void> _uploadImage() async {
    HapticFeedback.lightImpact();
    if (_selectedImages.isEmpty) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('XÃ¡c nháº­n ÄÄƒng áº¢nh'),
          content: Text(
            'Báº¡n cÃ³ cháº¯c cháº¯n muá»‘n Ä‘Äƒng ${_selectedImages.length} bá»©c áº£nh nÃ y lÃªn Bá»™ SÆ°u Táº­p chung khÃ´ng?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Há»§y'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Äá»“ng Ã½'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() {
      _isUploading = true;
      _uploadStatus = "Báº¯t Ä‘áº§u táº£i lÃªn...";
    });

    try {
      // Sao chÃ©p danh sÃ¡ch áº£nh cÅ© Ä‘á»ƒ tÃ­nh index chÃ­nh xÃ¡c
      List<Map<String, dynamic>> currentImages = List.from(widget.images);

      for (int i = 0; i < _selectedImages.length; i++) {
        final image = _selectedImages[i];
        setState(() {
          _uploadStatus = "Äang xá»­ lÃ½ ${i + 1}/${_selectedImages.length}...";
        });

        // NÃ©n & chuyá»ƒn sang webp
        final Uint8List? compressedBytes =
            await FlutterImageCompress.compressWithFile(
              image.path,
              minWidth: 1920,
              minHeight: 1920,
              quality: 80,
              format: CompressFormat.webp,
            );

        if (compressedBytes == null) continue;

        // TÃ­nh tÃªn file (tÃ¬m sá»‘ trá»‘ng nhá» nháº¥t)
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

        // Giáº£ láº­p cáº­p nháº­t danh sÃ¡ch local Ä‘á»ƒ áº£nh tiáº¿p theo khÃ´ng trÃ¹ng index
        currentImages.add({'index': nextIndex});
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ÄÃ£ táº£i táº¥t cáº£ áº£nh lÃªn thÃ nh cÃ´ng!')),
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
        ).showSnackBar(SnackBar(content: Text('Lá»—i táº£i lÃªn: $e')));
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
              title: Text('ÄÃ£ chá»n ${_selectedImages.length} áº£nh'),
              actions: [
                IconButton(
                  onPressed: _clearSelection,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  tooltip: 'XÃ³a háº¿t',
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
                        child: FilledButton.icon(
                          onPressed: _uploadImage,
                          icon: const Icon(Icons.cloud_upload),
                          label: const Text('ÄÄƒng táº¥t cáº£ áº£nh'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_photo_alternate_outlined, size: 80),
                      const SizedBox(height: 32),
                      FilledButton(
                        onPressed: _pickImage,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                        ),
                        child: const Text('Chá»n áº£nh tá»« thiáº¿t bá»‹'),
                      ),
                    ],
                  ),
                ),
    );
  }
}

// ----------------------------------------------------------------------
// 3. TRANG DELETE (XÃ³a áº£nh)
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
          title: const Text('XÃ¡c nháº­n XÃ³a áº¢nh'),
          content: Text('Báº¡n cÃ³ cháº¯c cháº¯n muá»‘n xÃ³a vÄ©nh viá»…n ${_selectedSha.length} bá»©c áº£nh Ä‘Ã£ chá»n khá»i Bá»™ SÆ°u Táº­p khÃ´ng? HÃ nh Ä‘á»™ng nÃ y khÃ´ng thá»ƒ hoÃ n tÃ¡c.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Há»§y'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('XÃ³a vÄ©nh viá»…n'),
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
        // TÃ¬m thÃ´ng tin file theo sha
        final img = widget.images.firstWhere((e) => e['sha'] == sha);
        await GithubService.deleteImage(img['path'], sha);
        successCount++;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ÄÃ£ xÃ³a thÃ nh cÃ´ng $successCount áº£nh')),
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
        ).showSnackBar(SnackBar(content: Text('Lá»—i xÃ³a áº£nh: $e')));
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
            Text("Äang xÃ³a áº£nh..."),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'ÄÃ£ chá»n ${_selectedSha.length} áº£nh Ä‘á»ƒ xÃ³a',
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
                  child: const Text('ThoÃ¡t'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton(
                  onPressed: _selectedSha.isEmpty ? null : _deleteSelected,
                  child: const Text('XÃ³a má»¥c Ä‘Ã£ chá»n'),
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
// 4. TRANG SETTINGS (CÃ i Ä‘áº·t & Lá»‹ch sá»­)
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
    // Má»—i khi vÃ o tab Settings, Ã©p cáº­p nháº­t láº¡i sá»‘ Hz tháº­t
    _updateHz();
  }

  Future<void> _updateHz() async {
    // KhÃ´ng lÃ m gÃ¬ cáº£ vÃ¬ Ä‘Ã£ xÃ³a chá»©c nÄƒng liÃªn quan táº§n sá»‘ quÃ©t.
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const ClampingScrollPhysics(), // Táº¯t hiá»‡u á»©ng kÃ©o giÃ£n cao su
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
            'Giao diá»‡n hiá»ƒn thá»‹',
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
                    title: Text('Theo há»‡ thá»‘ng'),
                    secondary: Icon(Icons.brightness_auto),
                    value: ThemeMode.system,
                  ),
                  const RadioListTile<ThemeMode>(
                    title: Text('Cháº¿ Ä‘á»™ sÃ¡ng'),
                    secondary: Icon(Icons.wb_sunny_rounded),
                    value: ThemeMode.light,
                  ),
                  const RadioListTile<ThemeMode>(
                    title: Text('Cháº¿ Ä‘á»™ tá»‘i'),
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
            'MÃ u chá»§ Ä‘áº¡o',
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
                    onTap: () async {
                      HapticFeedback.selectionClick();
                      MyApp.themeColorNotifier.value = color;
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setInt('themeColor', color.value);
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

// ----------------------------------------------------------------------
// 5. WIDGET XEM áº¢NH TOÃ€N MÃ€N HÃŒNH (Full Screen Viewer)
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

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  final TransformationController _transformationController =
      TransformationController();
  Offset _dragOffset = Offset.zero;
  double _scale = 1.0;
  bool _isDragging = false;
  int _pointerCount = 0; // Äáº¿m sá»‘ lÆ°á»£ng ngÃ³n tay trÃªn mÃ n hÃ¬nh

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Äá»™ má» cá»§a ná»n dá»±a trÃªn khoáº£ng cÃ¡ch kÃ©o (tá»‘i Ä‘a 300px)
    final double opacity =
        (1.0 - (_dragOffset.distance / 300)).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: opacity),
      body: Stack(
        children: [
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              setState(() {
                _pointerCount++;
              });
            },
            onPointerMove: (event) {
              final scale = _transformationController.value.getMaxScaleOnAxis();

              // Chá»‰ cho phÃ©p kÃ©o thoÃ¡t náº¿u:
              // 1. Chá»‰ cÃ³ 1 ngÃ³n tay cháº¡m
              // 2. KhÃ´ng Ä‘ang phÃ³ng to (scale <= 1.0)
              if (_pointerCount == 1 && scale <= 1.0) {
                if (!_isDragging) {
                  // Náº¿u chÆ°a báº¯t Ä‘áº§u kÃ©o, kiá»ƒm tra xem Ä‘Ã£ di chuyá»ƒn Ä‘á»§ xa chÆ°a (threshold)
                  if (event.localDelta.distance > 2) {
                    setState(() {
                      _isDragging = true;
                    });
                  }
                }

                if (_isDragging) {
                  setState(() {
                    _dragOffset += event.delta;
                    final double distance = _dragOffset.distance;
                    _scale = (1.0 - (distance / 1500)).clamp(0.6, 1.0);
                  });
                }
              } else if (_pointerCount > 1) {
                // Náº¿u cÃ³ nhiá»u hÆ¡n 1 ngÃ³n tay, há»§y tráº¡ng thÃ¡i kÃ©o thoÃ¡t ngay láº­p tá»©c
                if (_isDragging) {
                  setState(() {
                    _isDragging = false;
                    _dragOffset = Offset.zero;
                    _scale = 1.0;
                  });
                }
              }
            },
            onPointerUp: (event) {
              setState(() {
                _pointerCount--;
              });

              if (_pointerCount == 0 && _isDragging) {
                if (_dragOffset.distance > 100) {
                  Navigator.of(context).pop();
                } else {
                  setState(() {
                    _isDragging = false;
                    _dragOffset = Offset.zero;
                    _scale = 1.0;
                  });
                }
              }
            },
            onPointerCancel: (event) {
              setState(() {
                _pointerCount = 0;
                _isDragging = false;
                _dragOffset = Offset.zero;
                _scale = 1.0;
              });
            },
            child: Transform.translate(
              offset: _dragOffset,
              child: Transform.scale(
                scale: _scale,
                child: Center(
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    minScale: 1.0,
                    maxScale: 5.0,
                    panEnabled: !_isDragging,
                    scaleEnabled: !_isDragging,
                    child: Hero(
                      tag: widget.imageUrl,
                      flightShuttleBuilder: (
                        flightContext,
                        animation,
                        flightDirection,
                        fromHeroContext,
                        toHeroContext,
                      ) {
                        return AnimatedBuilder(
                          animation: animation,
                          builder: (context, child) {
                            return CachedNetworkImage(
                              imageUrl: widget.imageUrl,
                              fit: BoxFit.cover,
                              fadeInDuration: Duration.zero,
                              fadeOutDuration: Duration.zero,
                            );
                          },
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
        ],
      ),
    );
  }
}
