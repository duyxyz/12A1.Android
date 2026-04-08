import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/models/app_release.dart';
import '../../data/repositories/update_repository.dart';
import 'package:package_info_plus/package_info_plus.dart';

class UpdateViewModel extends ChangeNotifier {
  final UpdateRepository _updateRepository;

  UpdateViewModel(this._updateRepository);

  AppRelease? _latestRelease;
  bool _isChecking = false;
  String? _error;

  AppRelease? get latestRelease => _latestRelease;
  bool get isChecking => _isChecking;
  String? get error => _error;

  Future<void> checkForUpdates() async {
    _isChecking = true;
    _error = null;
    notifyListeners();

    try {
      final release = await _updateRepository.getLatestRelease();
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;
      
      if (_isNewerVersion(release.version, currentVersion)) {
        _latestRelease = release;
      } else {
        _latestRelease = null;
      }
      _isChecking = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isChecking = false;
      notifyListeners();
    }
  }

  bool _isNewerVersion(String remote, String local) {
    try {
      List<int> remoteParts = remote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      List<int> localParts = local.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      int maxLength = remoteParts.length > localParts.length ? remoteParts.length : localParts.length;

      for (int i = 0; i < maxLength; i++) {
        int r = i < remoteParts.length ? remoteParts[i] : 0;
        int l = i < localParts.length ? localParts[i] : 0;
        if (r > l) return true;
        if (r < l) return false;
      }
      return false;
    } catch (_) {
      return remote != local;
    }
  }

  Future<AppAsset?> findBestAssetFromRelease(AppRelease release) async {
    return await _updateRepository.findBestAsset(release.assets);
  }

  void clearUpdate() {
    _latestRelease = null;
    notifyListeners();
  }
}
