import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/main_screen.dart';
import 'services/supabase_service.dart';
import 'utils/scroll_behavior.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();
  
  final prefs = await SharedPreferences.getInstance();
  
  final themeIndex = prefs.getInt('themeMode') ?? 0;
  final colorValue = prefs.getInt('themeColor') ?? Colors.blueAccent.value;
  final hapticsEnabled = prefs.getBool('hapticsEnabled') ?? true;
  final gridCols = prefs.getInt('gridColumns') ?? 2;
  
  // themeIndex: 0=system, 1=light, 2=dark (OLED)
  MyApp.themeIndexNotifier.value = themeIndex == 3 ? 2 : themeIndex;
  MyApp.themeColorNotifier.value = Color(colorValue);
  MyApp.hapticNotifier.value = hapticsEnabled;
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

  static final ValueNotifier<int> gridColumnsNotifier = ValueNotifier(2);

  static final ValueNotifier<TargetPlatform?> platformNotifier = ValueNotifier(null);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: themeIndexNotifier,
      builder: (context, currentThemeIndex, _) {
        final themeMode = currentThemeIndex == 2
            ? ThemeMode.dark
            : (currentThemeIndex == 1 ? ThemeMode.light : ThemeMode.system);

        return ValueListenableBuilder<Color>(
          valueListenable: themeColorNotifier,
          builder: (context, currentColor, _) {
            final lightTheme = ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: currentColor,
              ),
              useMaterial3: true,
            );

            final darkTheme = ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: currentColor,
                brightness: Brightness.dark,
                surface: Colors.black,
                surfaceContainer: Colors.black,
                surfaceContainerLow: const Color(0xFF0D0D0D),
                surfaceContainerHigh: const Color(0xFF1A1A1A),
              ),
              scaffoldBackgroundColor: Colors.black,
              appBarTheme: const AppBarTheme(
                backgroundColor: Colors.black,
                elevation: 0,
              ),
              navigationBarTheme: const NavigationBarThemeData(
                backgroundColor: Colors.black,
                indicatorColor: Colors.transparent,
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
              home: const MainScreen(),
            );
          },
        );
      },
    );
  }
}
