import 'package:flutter/services.dart';
import '../main.dart';

class AppHaptics {
  static void lightImpact() {
    if (AppDependencies.instance.configViewModel.hapticsEnabled)
      HapticFeedback.lightImpact();
  }

  static void mediumImpact() {
    if (AppDependencies.instance.configViewModel.hapticsEnabled)
      HapticFeedback.mediumImpact();
  }

  static void heavyImpact() {
    if (AppDependencies.instance.configViewModel.hapticsEnabled)
      HapticFeedback.heavyImpact();
  }

  static void selectionClick() {
    if (AppDependencies.instance.configViewModel.hapticsEnabled)
      HapticFeedback.selectionClick();
  }
}
