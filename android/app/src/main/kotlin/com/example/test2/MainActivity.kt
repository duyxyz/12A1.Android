package com.example.test2

import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Yêu cầu tốc độ làm mới cao nhất (120Hz+) nếu phần cứng hỗ trợ
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val window = activity.window
            val params = window.attributes
            params.preferredDisplayModeId = 0 // Tự động chọn mode tốt nhất
            window.attributes = params
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val window = activity.window
            val params = window.attributes
            @Suppress("DEPRECATION")
            val display = windowManager.defaultDisplay
            val modes = display.supportedModes
            if (modes != null && modes.isNotEmpty()) {
                var maxRefreshRate = 0f
                var bestModeId = 0
                for (mode in modes) {
                    if (mode.refreshRate > maxRefreshRate) {
                        maxRefreshRate = mode.refreshRate
                        bestModeId = mode.modeId
                    }
                }
                if (bestModeId != 0) {
                    params.preferredDisplayModeId = bestModeId
                    window.attributes = params
                }
            }
        }
    }
}
