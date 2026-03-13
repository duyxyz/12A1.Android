import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/main_screen.dart';
import 'services/supabase_service.dart';
import 'widgets/auth_wrapper.dart';
import 'utils/scroll_behavior.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();
  
  final prefs = await SharedPreferences.getInstance();
  
  final themeIndex = prefs.getInt('themeMode') ?? 0;
  final colorValue = prefs.getInt('themeColor') ?? Colors.blueAccent.value;
  final hapticsEnabled = prefs.getBool('hapticsEnabled') ?? true;
  final lockEnabled = prefs.getBool('lockEnabled') ?? false;
  final gridCols = prefs.getInt('gridColumns') ?? 2;
  
  // themeIndex: 0=system, 1=light, 2=dark, 3=oled
  MyApp.themeIndexNotifier.value = themeIndex;
  MyApp.themeColorNotifier.value = Color(colorValue);
  MyApp.hapticNotifier.value = hapticsEnabled;
  MyApp.lockNotifier.value = lockEnabled;
  MyApp.gridColumnsNotifier.value = gridCols;
  MyApp.platformNotifier.value = null; // No longer manual override by default

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static final ValueNotifier<int> themeIndexNotifier = ValueNotifier(0);
  
  static final ValueNotifier<Color> themeColorNotifier = ValueNotifier(
    Colors.blueAccent,
  );

  static final ValueNotifier<bool> hapticNotifier = ValueNotifier(true);

  static final ValueNotifier<bool> lockNotifier = ValueNotifier(false);

  static final ValueNotifier<int> gridColumnsNotifier = ValueNotifier(2);

  static final ValueNotifier<TargetPlatform?> platformNotifier = ValueNotifier(null);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: themeIndexNotifier,
      builder: (context, currentThemeIndex, _) {
        final isOled = currentThemeIndex == 3;
        final themeMode = currentThemeIndex == 3 
            ? ThemeMode.dark 
            : (currentThemeIndex < 3 ? ThemeMode.values[currentThemeIndex] : ThemeMode.system);

        return ValueListenableBuilder<Color>(
          valueListenable: themeColorNotifier,
          builder: (context, currentColor, _) {
            final lightTheme = ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: currentColor),
              useMaterial3: true,
            );

            final darkTheme = ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: currentColor,
                brightness: Brightness.dark,
                surface: isOled ? Colors.black : null,
                surfaceContainer: isOled ? Colors.black : null,
                surfaceContainerLow: isOled ? const Color(0xFF0D0D0D) : null,
                surfaceContainerHigh: isOled ? const Color(0xFF1A1A1A) : null,
              ),
              scaffoldBackgroundColor: isOled ? Colors.black : null,
              appBarTheme: AppBarTheme(
                backgroundColor: isOled ? Colors.black : null,
                elevation: 0,
              ),
              navigationBarTheme: NavigationBarThemeData(
                backgroundColor: isOled ? Colors.black : null,
                indicatorColor: isOled ? currentColor.withValues(alpha: 0.2) : null,
              ),
              useMaterial3: true,
            );

            return MaterialApp(
              title: '12A1 THPT Đơn Dương',
              scrollBehavior: NoStretchScrollBehavior(),
              theme: lightTheme,
              darkTheme: darkTheme,
              themeMode: themeMode,
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
