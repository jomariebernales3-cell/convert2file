import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/auth_service.dart';
import 'services/local_llama_service.dart';
import 'services/supabase_config.dart';
import 'services/theme_service.dart';
import 'screens/ai_model_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/admin_login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/app_info_screen.dart';
import 'screens/bug_report_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/qr_code_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/study_builder_screen.dart';
import 'screens/text_to_file_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
  }

  final authService = AuthService();
  try {
    await authService.init().timeout(const Duration(seconds: 8));
  } on Object {
    // Never keep the app on the native launch screen because of stale cache.
  }
  await ThemeService.instance.init(userId: authService.currentUser?.id);
  await LocalLlamaService.instance.init();

  runApp(SmartTemplateApp(authService: authService));
}

class SmartTemplateApp extends StatelessWidget {
  final AuthService authService;

  const SmartTemplateApp({super.key, required this.authService});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeService.instance,
      builder: (context, _) {
        final themeService = ThemeService.instance;
        const day = _AppThemeColors(
          primary: Color(0xFF111827),
          secondary: Color(0xFF374151),
          background: Color(0xFFF7F8FA),
          surface: Colors.white,
          soft: Color(0xFFF1F3F6),
          line: Color(0xFFE2E5EA),
          text: Color(0xFF111827),
          muted: Color(0xFF6B7280),
        );
        const night = _AppThemeColors(
          primary: Colors.white,
          secondary: Color(0xFFD1D5DB),
          background: Color(0xFF05070B),
          surface: Color(0xFF0F1218),
          soft: Color(0xFF181D25),
          line: Color(0xFF303744),
          text: Colors.white,
          muted: Color(0xFFA7AFBC),
        );
        const dbz = _AppThemeColors(
          primary: Color(0xFF67E8F9),
          secondary: Color(0xFFA78BFA),
          background: Color(0xFF050611),
          surface: Color(0xFF101326),
          soft: Color(0xFF181B36),
          line: Color(0xFF39406E),
          text: Colors.white,
          muted: Color(0xFFB8C0E6),
        );

        return MaterialApp(
          title: 'Convert2File',
          debugShowCheckedModeBanner: false,
          themeMode: themeService.themeMode,
          theme: ThemeData(
            brightness: Brightness.light,
            primaryColor: day.primary,
            scaffoldBackgroundColor: day.background,
            dividerColor: day.line,
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFF7F8FA),
              foregroundColor: Color(0xFF111827),
              elevation: 0,
              centerTitle: true,
              titleTextStyle: TextStyle(
                color: Color(0xFF111827),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            cardTheme: CardThemeData(
              color: Colors.white,
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: day.line),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: day.surface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: day.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: day.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: day.primary, width: 1.6),
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: day.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE5E7EB),
                disabledForegroundColor: const Color(0xFF9CA3AF),
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                foregroundColor: day.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                side: BorderSide(color: day.primary.withValues(alpha: 0.7)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: day.primary),
            ),
            drawerTheme: const DrawerThemeData(
              backgroundColor: Color(0xFFF5F6F8),
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.horizontal(right: Radius.circular(8)),
              ),
            ),
            snackBarTheme: SnackBarThemeData(
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            colorScheme: ColorScheme.light(
              primary: day.primary,
              secondary: day.secondary,
              surface: day.surface,
              surfaceContainerHighest: day.soft,
              onPrimary: Colors.white,
              onSecondary: Colors.white,
              onSurface: day.text,
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: themeService.isDbzTheme ? dbz.primary : night.primary,
            scaffoldBackgroundColor:
                themeService.isDbzTheme ? dbz.background : night.background,
            dividerColor: themeService.isDbzTheme ? dbz.line : night.line,
            appBarTheme: AppBarTheme(
              backgroundColor:
                  themeService.isDbzTheme ? dbz.background : night.background,
              foregroundColor: Colors.white,
              elevation: 0,
              centerTitle: true,
              titleTextStyle: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            cardTheme: CardThemeData(
              color: themeService.isDbzTheme ? dbz.surface : night.surface,
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: themeService.isDbzTheme ? dbz.line : night.line,
                ),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: themeService.isDbzTheme ? dbz.surface : night.surface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: themeService.isDbzTheme ? dbz.line : night.line,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: themeService.isDbzTheme ? dbz.line : night.line,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: themeService.isDbzTheme ? dbz.primary : night.primary,
                  width: 1.6,
                ),
              ),
              labelStyle: const TextStyle(color: Colors.grey),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    themeService.isDbzTheme ? dbz.primary : night.primary,
                foregroundColor:
                    themeService.isDbzTheme ? Colors.black : Colors.black,
                disabledBackgroundColor: const Color(0xFF2A3038),
                disabledForegroundColor: const Color(0xFF737B86),
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    themeService.isDbzTheme ? dbz.primary : night.primary,
                side: BorderSide(
                  color: themeService.isDbzTheme
                      ? dbz.primary
                      : night.primary.withValues(alpha: 0.75),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor:
                    themeService.isDbzTheme ? dbz.primary : night.primary,
              ),
            ),
            drawerTheme: DrawerThemeData(
              backgroundColor:
                  themeService.isDbzTheme ? dbz.background : night.background,
              shape: const RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.horizontal(right: Radius.circular(8)),
              ),
            ),
            snackBarTheme: SnackBarThemeData(
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            colorScheme: ColorScheme.dark(
              primary: themeService.isDbzTheme ? dbz.primary : night.primary,
              secondary:
                  themeService.isDbzTheme ? dbz.secondary : night.secondary,
              surface: themeService.isDbzTheme ? dbz.surface : night.surface,
              surfaceContainerHighest:
                  themeService.isDbzTheme ? dbz.soft : night.soft,
              onPrimary: Colors.black,
              onSecondary: Colors.black,
              onSurface: Colors.white,
            ),
            useMaterial3: true,
          ),
          initialRoute: '/splash',
          routes: {
            '/splash': (context) => const SplashScreen(),
            '/login': (context) => const LoginScreen(),
            '/home': (context) => const HomeScreen(),
            '/dashboard': (context) => const DashboardScreen(),
            '/history': (context) => const HistoryScreen(),
            '/saved-files': (context) =>
                const HistoryScreen(savedFilesMode: true),
            '/app-info': (context) => const AppInfoScreen(),
            '/bug-report': (context) => const BugReportScreen(),
            '/profile': (context) => const ProfileScreen(),
            '/settings': (context) => const SettingsScreen(),
            '/ai-model': (context) => const AiModelScreen(),
            '/admin': (context) => const AdminDashboardScreen(),
            '/admin-login': (context) => const AdminLoginScreen(),
            '/study-builder': (context) => const StudyBuilderScreen(),
            '/generate-quiz': (context) =>
                const StudyBuilderScreen(generateQuizOnly: true),
            '/qr-code': (context) => const QrCodeScreen(),
            '/text-to-file': (context) => const TextToFileScreen(),
          },
        );
      },
    );
  }
}

class _AppThemeColors {
  final Color primary;
  final Color secondary;
  final Color background;
  final Color surface;
  final Color soft;
  final Color line;
  final Color text;
  final Color muted;

  const _AppThemeColors({
    required this.primary,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.soft,
    required this.line,
    required this.text,
    required this.muted,
  });
}
