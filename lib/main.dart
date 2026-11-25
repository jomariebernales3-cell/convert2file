import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'widgets/bootstrap_icon.dart';
import 'services/auth_service.dart';
import 'services/local_llama_service.dart';
import 'services/supabase_config.dart';
import 'services/theme_service.dart';
import 'theme/app_colors.dart';
import 'screens/ai_model_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/offline_ai_chat_screen.dart';
import 'screens/login_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/app_info_screen.dart';
import 'screens/bug_report_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/edit_profile_screen.dart';
import 'screens/change_password_screen.dart';
import 'screens/app_lock_settings_screen.dart';
import 'widgets/app_lock_gate.dart';
import 'services/app_lock_service.dart';
import 'screens/qr_code_screen.dart';
import 'screens/qr_output_screen.dart';
import 'screens/announcements_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/study_builder_screen.dart';
import 'screens/text_to_file_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const Convert2FileBootstrap());
}

class Convert2FileBootstrap extends StatefulWidget {
  const Convert2FileBootstrap({super.key});

  @override
  State<Convert2FileBootstrap> createState() => _Convert2FileBootstrapState();
}

class _Convert2FileBootstrapState extends State<Convert2FileBootstrap> {
  AuthService? _authService;
  Object? _startupError;
  bool _supabaseInitialized = false;
  bool _nativeSplashReleased = false;
  static const _startupSplashChannel = MethodChannel(
    'convert2file/startup_splash',
  );

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      if (SupabaseConfig.isConfigured && !_supabaseInitialized) {
        await Supabase.initialize(
          url: SupabaseConfig.url,
          anonKey: SupabaseConfig.anonKey,
        );
        _supabaseInitialized = true;
      }

      final authService = AuthService();
      try {
        await authService.init().timeout(const Duration(seconds: 8));
      } on Object {
        // Continue to the app if cached authentication data is unavailable.
      }
      await ThemeService.instance.init(userId: authService.currentUser?.id);
      await LocalLlamaService.instance.init();
      await AppLockService.instance.initialize();

      if (!mounted) return;
      setState(() {
        _authService = authService;
        _startupError = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _startupError = error);
    } finally {
      await WidgetsBinding.instance.endOfFrame;
      await _dismissNativeSplash();
    }
  }

  Future<void> _dismissNativeSplash() async {
    if (_nativeSplashReleased) return;
    _nativeSplashReleased = true;
    try {
      await _startupSplashChannel.invokeMethod<void>('dismiss');
    } on Object {
      // The native loading overlay is only installed on Android.
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = _authService;
    if (authService != null) {
      return SmartTemplateApp(authService: authService);
    }

    return AnimatedBuilder(
      animation: ThemeService.instance,
      builder: (context, _) => MaterialApp(
        title: 'Convert2File',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeService.instance.themeMode,
        theme: _buildAppTheme(AppColors.day, Brightness.light),
        darkTheme: _buildAppTheme(AppColors.night, Brightness.dark),
        home: _startupError == null
            ? const SizedBox.expand()
            : _StartupFailureScreen(onRetry: _initializeApp),
      ),
    );
  }
}

class _StartupFailureScreen extends StatefulWidget {
  final Future<void> Function() onRetry;

  const _StartupFailureScreen({required this.onRetry});

  @override
  State<_StartupFailureScreen> createState() => _StartupFailureScreenState();
}

class _StartupFailureScreenState extends State<_StartupFailureScreen> {
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    await widget.onRetry();
    if (mounted) setState(() => _retrying = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BootstrapIcon.material(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              Text(
                'Convert2File could not finish starting.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              const Text(
                'Please try again. If the problem continues, restart the app.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _retrying ? null : _retry,
                icon: _retrying
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const BootstrapIcon.material(Icons.refresh),
                label: Text(_retrying ? 'Retrying…' : 'Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
        return MaterialApp(
          builder: (context, child) =>
              AppLockGate(child: child ?? const SizedBox.shrink()),
          title: 'Convert2File',
          debugShowCheckedModeBanner: false,
          themeMode: themeService.themeMode,
          theme: _buildAppTheme(AppColors.day, Brightness.light),
          darkTheme: _buildAppTheme(
            AppColors.night,
            Brightness.dark,
          ),
          initialRoute: authService.isLoggedIn ? '/home' : '/login',
          routes: {
            '/login': (context) => const LoginScreen(),
            '/forgot-password': (context) => ForgotPasswordScreen(
                  initialEmail:
                      ModalRoute.of(context)?.settings.arguments as String?,
                ),
            '/home': (context) => const HomeScreen(),
            '/offline-ai': (context) => const OfflineAiChatScreen(),
            '/dashboard': (context) => const DashboardScreen(),
            '/history': (context) => const HistoryScreen(),
            '/saved-files': (context) =>
                const HistoryScreen(savedFilesMode: true),
            '/app-info': (context) => const AppInfoScreen(),
            '/bug-report': (context) => const BugReportScreen(),
            '/profile': (context) => const ProfileScreen(),
            '/edit-profile': (context) => const EditProfileScreen(),
            '/change-password': (context) => const ChangePasswordScreen(),
            '/app-lock': (context) => const AppLockSettingsScreen(),
            '/settings': (context) => const SettingsScreen(),
            '/ai-model': (context) => const AiModelScreen(),
            '/study-builder': (context) => const StudyBuilderScreen(),
            '/generate-quiz': (context) =>
                const StudyBuilderScreen(generateQuizOnly: true),
            '/qr-code': (context) => const QrCodeScreen(),
            '/qr-output': (context) => QrOutputScreen(
                  file: ModalRoute.of(context)!.settings.arguments
                      as Map<String, dynamic>,
                ),
            '/announcements': (context) => const AnnouncementsScreen(),
            '/text-to-file': (context) => const TextToFileScreen(),
          },
        );
      },
    );
  }
}

ThemeData _buildAppTheme(AppColors colors, Brightness brightness) {
  final isLight = brightness == Brightness.light;
  final colorScheme = isLight
      ? ColorScheme.light(
          primary: colors.accent,
          secondary: colors.accent,
          surface: colors.surface,
          surfaceContainerHighest: colors.surface2,
          onPrimary: colors.accentInk,
          onSecondary: colors.accentInk,
          onSurface: colors.text,
          error: colors.danger,
          onError: colors.text,
        )
      : ColorScheme.dark(
          primary: colors.accent,
          secondary: colors.accent,
          surface: colors.surface,
          surfaceContainerHighest: colors.surface2,
          onPrimary: colors.accentInk,
          onSecondary: colors.accentInk,
          onSurface: colors.text,
          error: colors.danger,
          onError: colors.text,
        );

  return ThemeData(
    brightness: brightness,
    colorScheme: colorScheme,
    extensions: <ThemeExtension<dynamic>>[colors],
    primaryColor: colors.accent,
    scaffoldBackgroundColor: colors.background,
    dividerColor: colors.line,
    hintColor: colors.muted,
    disabledColor: colors.muted.withValues(alpha: 0.55),
    textTheme: (isLight ? ThemeData.light() : ThemeData.dark())
        .textTheme
        .apply(bodyColor: colors.text, displayColor: colors.text),
    iconTheme: IconThemeData(color: colors.text),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.background,
      foregroundColor: colors.text,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: colors.text,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: colors.surface,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface,
      hintStyle: TextStyle(color: colors.muted),
      labelStyle: TextStyle(color: colors.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.accent, width: 1.6),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.accent,
        foregroundColor: colors.accentInk,
        disabledBackgroundColor: colors.surface2,
        disabledForegroundColor: colors.muted,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.accent,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        side: BorderSide(color: colors.accent.withValues(alpha: 0.7)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: colors.accent),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? colors.accent
                : colors.surface2),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? colors.accentInk
                : colors.muted),
        side: const WidgetStatePropertyAll(BorderSide.none),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(8)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.surface2,
      contentTextStyle: TextStyle(color: colors.text),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: colors.accent),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.accent,
      selectionColor: colors.accent.withValues(alpha: 0.25),
      selectionHandleColor: colors.accent,
    ),
    useMaterial3: true,
  );
}
