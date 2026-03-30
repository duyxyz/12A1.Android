import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/repositories/image_repository.dart';
import 'data/repositories/update_repository.dart';
import 'data/services/github_api_service.dart';
import 'data/services/supabase_api_service.dart';
import 'logic/viewmodels/app_config_view_model.dart';
import 'logic/viewmodels/home_view_model.dart';
import 'logic/viewmodels/update_view_model.dart';
import 'screens/main_screen.dart';
import 'utils/scroll_behavior.dart';
import 'services/favorite_service.dart';

// Dependencies Container
class AppDependencies {
  final AppConfigViewModel configViewModel;
  final HomeViewModel homeViewModel;
  final UpdateViewModel updateViewModel;
  final ImageRepository imageRepository;

  AppDependencies({
    required this.configViewModel,
    required this.homeViewModel,
    required this.updateViewModel,
    required this.imageRepository,
  });

  static late AppDependencies _instance;
  static AppDependencies get instance => _instance;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. Initialize Supabase
    const supabaseUrl = 'https://pplwdupvhmypmkjxcxpr.supabase.co';
    const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBwbHdkdXB2aG15cG1ranhjeHByIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwNTc3NzEsImV4cCI6MjA4ODYzMzc3MX0.UikH-oZ3vC72RL8PPIzgUr6N12Mq6Pk8aGLqri7PGiM';
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    
    // 2. Services
    await FavoriteService.init();
    
    final githubApi = GithubApiService(
      token: const String.fromEnvironment('GH_TOKEN'),
      owner: 'duyxyz',
      imageRepo: '12A1.Galary',
      appRepo: '12A1.Android',
      onRateLimitUpdate: (val) => AppDependencies.instance.configViewModel.updateApiRemaining(val),
    );
    final supabaseApi = SupabaseApiService(Supabase.instance.client);

    // 3. Repositories
    final imageRepo = ImageRepository(githubApi, supabaseApi);
    final updateRepo = UpdateRepository(githubApi);

    // 4. ViewModels
    _instance = AppDependencies(
      configViewModel: AppConfigViewModel(prefs),
      homeViewModel: HomeViewModel(imageRepo),
      updateViewModel: UpdateViewModel(updateRepo),
      imageRepository: imageRepo,
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDependencies.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  PageTransitionsTheme _androidPredictiveBackTransitions() {
    return const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = AppDependencies.instance.configViewModel;
    final pageTransitionsTheme = _androidPredictiveBackTransitions();

    return ListenableBuilder(
      listenable: config,
      builder: (context, _) {
        final lightTheme = ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: config.themeColor),
          pageTransitionsTheme: pageTransitionsTheme,
          useMaterial3: true,
        );

        final darkTheme = ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: config.themeColor,
            brightness: Brightness.dark,
            surface: Colors.black,
            surfaceContainer: Colors.black,
            surfaceContainerLow: const Color(0xFF0D0D0D),
            surfaceContainerHigh: const Color(0xFF1A1A1A),
          ),
          scaffoldBackgroundColor: Colors.black,
          appBarTheme: const AppBarTheme(backgroundColor: Colors.black, elevation: 0),
          navigationBarTheme: const NavigationBarThemeData(
            backgroundColor: Colors.black,
            indicatorColor: Colors.transparent,
          ),
          pageTransitionsTheme: pageTransitionsTheme,
          useMaterial3: true,
        );

        return MaterialApp(
          title: '12A1 THPT Đơn Dương',
          scrollBehavior: NoStretchScrollBehavior(),
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: config.themeMode,
          themeAnimationDuration: const Duration(milliseconds: 500),
          themeAnimationCurve: Curves.easeInOut,
          home: const MainScreen(),
        );
      },
    );
  }
}
