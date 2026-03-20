import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'dart:ui' as ui;

import '../main.dart';
import '../services/github_service.dart';
import '../services/supabase_service.dart';
import '../utils/haptics.dart';
import '../utils/update_manager.dart';
import '../widgets/pulse_skeleton.dart';
import '../widgets/error_view.dart';
import '../widgets/image_grid_item.dart';
import 'settings_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // --- Data State ---
  List<Map<String, dynamic>> _images = [];
  bool _isLoading = true;
  String _error = "";
  final ScrollController _scrollController = ScrollController();
  StreamSubscription? _metadataSubscription;
  Timer? _debounceTimer;

  // --- Upload State ---
  bool _isUploading = false;
  String _uploadStatus = "";
  final ImagePicker _picker = ImagePicker();
  List<XFile> _selectedToUpload = [];

  // --- Delete Selection State ---
  bool _isSelectionMode = false;
  bool _isDeleting = false;
  final Set<String> _selectedSha = {};

  @override
  void initState() {
    super.initState();
    _loadData();
    _setupRealtimeMetadata();
    _checkForUpdateSilent();
    cleanupUpdateFiles(); 
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _metadataSubscription?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }

  // ========================
  //  APP CORE & DATA
  // ========================

  void _setupRealtimeMetadata() {
    _metadataSubscription = SupabaseService.metadataStream().listen((data) {
      if (data.isNotEmpty && mounted) {
        bool hasChanges = false;
        if (_images.isNotEmpty) {
          final Map<int, double> newRatios = {
            for (var item in data)
              item['image_index'] as int: (item['aspect_ratio'] as num).toDouble(),
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
        if (hasChanges) setState(() {});
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(seconds: 3), () {
          if (mounted && data.length != _images.length) {
            _loadData();
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
      final latestVersion = updateData['tag_name'].toString().replaceAll('v', '');
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;

      if (latestVersion != currentVersion && mounted) {
        _showUpdateDialog(context, updateData);
      }
    }
  }

  void _showUpdateDialog(BuildContext context, Map<String, dynamic> updateData) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('🎉 Có bản cập nhật mới!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Phiên bản mới: ${updateData['tag_name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('Nội dung thay đổi:', style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 4),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: Text(updateData['body'] ?? 'Cập nhật tính năng mới và sửa lỗi.', style: const TextStyle(fontSize: 13)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Để sau')),
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

  // ========================
  //  UPLOAD FLOW
  // ========================

  Future<void> _pickImage() async {
    AppHaptics.lightImpact();
    // Tự động tắt chế độ xóa nếu đang kích hoạt
    if (_isSelectionMode) {
      _exitSelectionMode();
    }
    try {
      final List<XFile> images = await _picker.pickMultiImage();
      if (images.isNotEmpty) {
        setState(() {
          _selectedToUpload.addAll(images);
        });
        _showUploadSheet();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi chọn ảnh: $e')));
      }
    }
  }

  void _showUploadSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_upload_outlined, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 10),
                      Text('Đăng ${_selectedToUpload.length} ảnh', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(
                        onPressed: () {
                          setState(() => _selectedToUpload.clear());
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
                    itemCount: _selectedToUpload.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _selectedToUpload.length) {
                        return InkWell(
                          onTap: () async {
                            try {
                              final more = await _picker.pickMultiImage();
                              if (more.isNotEmpty) {
                                setState(() => _selectedToUpload.addAll(more));
                                setSheetState(() {});
                              }
                            } catch (_) {}
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant), borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.add_a_photo_outlined, size: 28),
                          ),
                        );
                      }
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(File(_selectedToUpload[index].path), fit: BoxFit.cover),
                            ),
                          ),
                          Positioned(
                            top: 4, right: 4,
                            child: GestureDetector(
                              onTap: () {
                                setState(() => _selectedToUpload.removeAt(index));
                                setSheetState(() {});
                                if (_selectedToUpload.isEmpty) Navigator.pop(ctx);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                child: const Icon(Icons.close, size: 16, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _uploadImages();
                      },
                      icon: const Icon(Icons.upload_rounded),
                      label: const Text('Đăng tất cả ảnh'),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _uploadImages() async {
    if (_selectedToUpload.isEmpty) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Xác nhận Đăng Ảnh'),
          content: Text('Bạn có chắc chắn muốn đăng ${_selectedToUpload.length} bức ảnh này lên Bộ Sưu Tập chung không?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Hủy')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Đồng ý')),
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
      List<Map<String, dynamic>> currentImages = List.from(_images);

      for (int i = 0; i < _selectedToUpload.length; i++) {
        final image = _selectedToUpload[i];
        setState(() {
          _uploadStatus = "Đang xử lý ${i + 1}/${_selectedToUpload.length}...";
        });

        final Uint8List? compressedBytes = await FlutterImageCompress.compressWithFile(
          image.path,
          minWidth: 1920, minHeight: 1920, quality: 80, format: CompressFormat.webp,
        );

        if (compressedBytes == null) continue;

        int nextIndex = 1;
        List<int> existingIndexes = currentImages.map<int>((img) => img['index'] as int).toList()..sort();
        for (int idx = 0; idx < existingIndexes.length; idx++) {
          if (existingIndexes[idx] == nextIndex) nextIndex++;
          else if (existingIndexes[idx] > nextIndex) break;
        }

        final filename = '$nextIndex.webp';
        await GithubService.uploadImage(filename, compressedBytes);

        try {
          final decodedImage = img.decodeImage(compressedBytes);
          if (decodedImage != null) {
            await SupabaseService.upsertImageMetadata(nextIndex, decodedImage.width, decodedImage.height);
          }
        } catch (e) {
          debugPrint('Lỗi lưu Supabase: $e');
        }

        currentImages.add({'index': nextIndex});
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã tải tất cả ảnh lên thành công!')));
        setState(() {
          _selectedToUpload.clear();
        });
      }
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi tải lên: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // ========================
  //  DELETE FLOW
  // ========================

  void _exitSelectionMode() {
    AppHaptics.lightImpact();
    setState(() {
      _isSelectionMode = false;
      _selectedSha.clear();
    });
  }

  void _toggleSelection(String sha) {
    AppHaptics.selectionClick();
    setState(() {
      if (_selectedSha.contains(sha)) {
        _selectedSha.remove(sha);
        if (_selectedSha.isEmpty) _isSelectionMode = false;
      } else {
        _selectedSha.add(sha);
      }
    });
  }

  void _enterSelectionMode() {
    AppHaptics.mediumImpact();
    setState(() {
      _isSelectionMode = true;
      _selectedSha.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Hãy chạm vào ảnh bạn muốn xóa.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _enterSelectionModeWithImage(String sha) {
    AppHaptics.mediumImpact();
    setState(() {
      _isSelectionMode = true;
      _selectedSha.add(sha);
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
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Hủy')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.of(context).pop(true), child: const Text('Xóa')),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() => _isDeleting = true);

    try {
      int successCount = 0;
      for (String sha in _selectedSha) {
        final image = _images.firstWhere((e) => e['sha'] == sha);
        await GithubService.deleteImage(image['path'], sha);
        if (image['index'] != null) {
          await SupabaseService.deleteImageMetadata(image['index'] as int);
        }
        successCount++;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã xóa thành công $successCount ảnh')));
      }
      setState(() {
        _selectedSha.clear();
        _isSelectionMode = false;
      });
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi xóa ảnh: $e')));
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  // ========================
  //  UI BUILDER
  // ========================

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // View: Error
    if (_error.isNotEmpty) {
      return Scaffold(
        body: ErrorView(message: 'Lỗi nạp dữ liệu: $_error', onRetry: _loadData, isFullScreen: true),
      );
    }

    // View: Uploading
    if (_isUploading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const PulseSkeleton(width: 100, height: 100),
              const SizedBox(height: 16),
              Text(_uploadStatus, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    // View: Deleting
    if (_isDeleting) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const PulseSkeleton(width: 80, height: 80),
              const SizedBox(height: 16),
              const Text("Đang xóa ảnh...", style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    // View: Main Grids
    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isSelectionMode) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        appBar: _isSelectionMode
            ? AppBar(
                leading: IconButton(icon: const Icon(Icons.close), onPressed: _exitSelectionMode),
                title: Text('Đã chọn ${_selectedSha.length}'),
                actions: [
                  if (_selectedSha.isNotEmpty)
                    IconButton(
                        icon: const Icon(Icons.delete_rounded),
                        color: colorScheme.error,
                        tooltip: 'Xóa ảnh đã chọn',
                        onPressed: _deleteSelected),
                ],
              )
            : null,
        body: SafeArea(
          child: Stack(
            children: [
              // Grid View
              if (_images.isEmpty && !_isLoading)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.photo_library_outlined, size: 80, color: colorScheme.outlineVariant),
                      const SizedBox(height: 16),
                      Text('Chưa có ảnh nào', style: TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      Text('Hãy chọn Thêm ảnh từ Menu', style: TextStyle(fontSize: 13, color: colorScheme.outline)),
                    ],
                  ),
                )
              else
                ValueListenableBuilder<int>(
                  valueListenable: MyApp.gridColumnsNotifier,
                  builder: (context, gridCols, _) {
                    return MasonryGridView.count(
                      controller: _scrollController,
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.all(4.0),
                      crossAxisCount: gridCols,
                      mainAxisSpacing: 4.0,
                      crossAxisSpacing: 4.0,
                      itemCount: _images.length,
                      itemBuilder: (context, index) {
                        final image = _images[index];
                        final isSelected = _selectedSha.contains(image['sha']);
                        
                        if (_isSelectionMode) {
                          // View inside Selection Mode
                          return GestureDetector(
                            onTap: () => _toggleSelection(image['sha']),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: isSelected ? Border.all(color: colorScheme.error, width: 3) : null,
                              ),
                              child: Stack(
                                fit: StackFit.loose,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(isSelected ? 7 : 10),
                                    child: CachedNetworkImage(
                                      imageUrl: image['download_url'],
                                      fit: BoxFit.cover,
                                      memCacheWidth: (MediaQuery.of(context).size.width * 0.4).round(),
                                      placeholder: (context, url) => const PulseSkeleton(borderRadius: BorderRadius.all(Radius.circular(10))),
                                      errorWidget: (context, url, error) => Container(color: colorScheme.errorContainer, padding: const EdgeInsets.all(20), child: const Icon(Icons.image_not_supported_rounded)),
                                    ),
                                  ),
                                  if (isSelected)
                                    Positioned.fill(
                                      child: Container(
                                        decoration: BoxDecoration(color: colorScheme.error.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(7)),
                                        child: const Center(child: Icon(Icons.check_circle_rounded, color: Colors.white, size: 32)),
                                      ),
                                    )
                                  else
                                    Positioned(
                                      top: 6, right: 6,
                                      child: Container(width: 22, height: 22, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white70, width: 2))),
                                    ),
                                ],
                              ),
                            ),
                          );
                        } else {
                          // Normal View
                          return GestureDetector(
                            onLongPress: () => _enterSelectionModeWithImage(image['sha']),
                            child: ImageGridItem(
                              imageUrl: image['download_url'],
                              aspectRatio: image['aspect_ratio'] as double,
                            ),
                          );
                        }
                      },
                    );
                  },
                ),
              // Loading Indicator
              if (_isLoading)
                const Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: SafeArea(child: LinearProgressIndicator()),
                ),
            ],
          ),
        ),
        floatingActionButton: _isSelectionMode
            ? null
            : PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'add':
                      _pickImage();
                      break;
                    case 'delete':
                      _enterSelectionMode();
                      break;
                    case 'settings':
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const SettingsScreen()),
                      );
                      break;
                  }
                },
                offset: const Offset(0, -140),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'add',
                    child: Row(
                      children: [
                        Icon(Icons.add_photo_alternate_outlined, color: colorScheme.primary),
                        const SizedBox(width: 12),
                        const Text('Thêm ảnh mới'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_sweep_outlined, color: colorScheme.error),
                        const SizedBox(width: 12),
                        Text('Xóa ảnh', style: TextStyle(color: colorScheme.error)),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'settings',
                    child: Row(
                      children: [
                        Icon(Icons.settings_outlined),
                        SizedBox(width: 12),
                        Text('Cài đặt hệ thống'),
                      ],
                    ),
                  ),
                ],
                child: FloatingActionButton(
                  onPressed: null, // Tap handled by PopupMenuButton
                  heroTag: 'menu_fab',
                  child: const Icon(Icons.menu_rounded),
                ),
              ),
      ),
    );
  }
}
