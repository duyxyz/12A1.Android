import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/github_service.dart';
import '../utils/haptics.dart';
import '../widgets/pulse_skeleton.dart';
import '../widgets/error_view.dart';

class DeleteTab extends StatefulWidget {
  final List<Map<String, dynamic>> images;
  final bool isLoading;
  final String error;
  final Future<void> Function() onRefresh;

  const DeleteTab({
    super.key,
    required this.images,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
  });

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
    if (widget.error.isNotEmpty) {
      return ErrorView(
        message: 'Lỗi nạp dữ liệu: ${widget.error}',
        onRetry: widget.onRefresh,
        isFullScreen: false,
      );
    }

    if (!_isAuthenticated) {
      return Center(
        child: InkWell(
          borderRadius: BorderRadius.circular(100),
          onTap: _authenticate,
          child: Container(
            padding: const EdgeInsets.all(48), 
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: const Icon(Icons.lock, size: 80), 
          ),
        ),
      );
    }

    if (_isDeleting) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const PulseSkeleton(width: 80, height: 80),
            const SizedBox(height: 16),
            const Text("Đang xóa ảnh...", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (widget.isLoading)
          const LinearProgressIndicator(),
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
                        memCacheWidth: (MediaQuery.of(context).size.width * 0.4).round(),
                        placeholder: (context, url) => const PulseSkeleton(
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: Theme.of(context).colorScheme.errorContainer,
                          child: const Icon(Icons.image_not_supported_rounded, size: 24),
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
