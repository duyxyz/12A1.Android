import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/models/gallery_image.dart';
import '../../data/repositories/image_repository.dart';

class HomeViewModel extends ChangeNotifier {
  final ImageRepository _imageRepository;

  HomeViewModel(this._imageRepository);

  List<GalleryImage> _images = [];
  bool _isLoading = false;
  String _error = "";
  StreamSubscription? _metadataSubscription;

  List<GalleryImage> get images => _images;
  bool get isLoading => _isLoading;
  String get error => _error;

  Future<void> loadImages() async {
    if (_isLoading) return;
    _isLoading = true;
    _error = "";
    notifyListeners();

    try {
      _images = await _imageRepository.getImages();
      _isLoading = false;
      _setupRealtimeSubscription();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Timer? _debounceTimer;

  void _setupRealtimeSubscription() {
    _metadataSubscription?.cancel();
    _metadataSubscription = _imageRepository.watchMetadata().listen((newMetadata) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 300), () {
        if (!hasListeners) return;
        
        final currentIndices = _images.map((img) => img.index).toSet();
        final newIndices = newMetadata.keys.toSet();

        // Check if any image was added or deleted by comparing indices
        if (newIndices.length != currentIndices.length || !newIndices.containsAll(currentIndices)) {
          // Mismatch found, need to reload full list to reflect file changes (URLs, SHAs) from GitHub
          loadImages();
        } else {
          // Same set of images, just update aspect ratios in-place for performance
          bool hasChanges = false;
          _images = _images.map((img) {
            final newRatio = newMetadata[img.index];
            if (newRatio != null && newRatio != img.aspectRatio) {
              hasChanges = true;
              return img.copyWith(aspectRatio: newRatio);
            }
            return img;
          }).toList();

          if (hasChanges) {
            notifyListeners();
          }
        }
      });
    });
  }

  Future<void> uploadImage(String filename, Uint8List bytes, int width, int height) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _imageRepository.uploadImage(filename, bytes, width, height);
      await loadImages();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteImage(GalleryImage image) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _imageRepository.deleteImage(image);
      await loadImages();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _metadataSubscription?.cancel();
    super.dispose();
  }
}
