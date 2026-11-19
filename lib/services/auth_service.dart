import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/database_helper.dart';
import '../models/user_model.dart';
import 'supabase_config.dart';
import 'app_version_service.dart';
import 'theme_service.dart';

class AuthService {
  static String? passwordValidationError(String password) {
    if (password.length < 8) return 'Use at least 8 characters.';
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Include at least one uppercase letter.';
    }
    if (!RegExp(r'\d').hasMatch(password)) {
      return 'Include at least one number.';
    }
    if (!RegExp(r'[^\w\s]').hasMatch(password)) {
      return 'Include at least one special character, such as ! or #.';
    }
    return null;
  }

  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  UserModel? _currentUser;
  StreamSubscription<AuthState>? _authSubscription;
  UserModel? get currentUser => _currentUser;

  bool get isLoggedIn =>
      _currentUser != null &&
      SupabaseConfig.isConfigured &&
      Supabase.instance.client.auth.currentSession != null;
  bool get isSupabaseConfigured => SupabaseConfig.isConfigured;

  Future<void> init() async {
    if (!SupabaseConfig.isConfigured) return;
    _authSubscription ??=
        Supabase.instance.client.auth.onAuthStateChange.listen((state) async {
      if (state.event == AuthChangeEvent.signedOut) {
        _currentUser = null;
      } else if (state.event == AuthChangeEvent.tokenRefreshed &&
          state.session != null) {
        try {
          await _syncAuthUser(state.session!.user);
        } on Object {/* Preserve offline use. */}
      }
    });
    final authUser = Supabase.instance.client.auth.currentUser;
    if (authUser != null) await _syncAuthUser(authUser);
  }

  Future<UserModel> requireLocalUser() async {
    if (_currentUser != null) return _currentUser!;
    if (SupabaseConfig.isConfigured) {
      final authUser = Supabase.instance.client.auth.currentUser;
      if (authUser != null) await _syncAuthUser(authUser);
    }
    if (_currentUser == null) await _loadLocalUser();
    return _currentUser!;
  }

  Future<void> signIn({required String email, required String password}) async {
    _requireSupabaseConfiguration();
    await _ensureOnlineServicesAvailable();

    final response = await Supabase.instance.client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    if (response.user == null) {
      throw const AuthException('Sign-in did not return a user.');
    }
    await _syncAuthUser(response.user!);
  }

  Future<void> resendConfirmationEmail({required String email}) async {
    _requireSupabaseConfiguration();
    await Supabase.instance.client.auth.resend(
      type: OtpType.signup,
      email: email.trim(),
    );
  }

  Future<void> sendPasswordRecoveryCode({required String email}) async {
    _requireSupabaseConfiguration();
    await Supabase.instance.client.auth.resetPasswordForEmail(email.trim());
  }

  Future<void> verifyPasswordRecoveryCode({
    required String email,
    required String code,
  }) async {
    _requireSupabaseConfiguration();
    await Supabase.instance.client.auth.verifyOTP(
      type: OtpType.recovery,
      token: code.trim(),
      email: email.trim(),
    );
  }

  Future<void> changePasswordWithCurrent({
    required String currentPassword,
    required String newPassword,
  }) async {
    final validationError = passwordValidationError(newPassword);
    if (validationError != null) throw AuthException(validationError);
    final user = await requireLocalUser();
    final authUser = SupabaseConfig.isConfigured
        ? Supabase.instance.client.auth.currentUser
        : null;
    if (authUser == null || user.supabaseUserId == null) {
      throw const AuthException(
          'Sign in to an account before changing its password.');
    }
    if (newPassword == currentPassword) {
      throw const AuthException(
          'Choose a new password that differs from the current password.');
    }
    await _ensureOnlineServicesAvailable();
    final verified = await Supabase.instance.client.auth.signInWithPassword(
      email: user.email,
      password: currentPassword,
    );
    if (verified.user?.id != authUser.id) {
      throw const AuthException('The current password is incorrect.');
    }
    await updatePassword(password: newPassword);
  }

  Future<void> updatePassword({required String password}) async {
    final validationError = passwordValidationError(password);
    if (validationError != null) throw AuthException(validationError);
    _requireSupabaseConfiguration();
    await Supabase.instance.client.auth.updateUser(
      UserAttributes(password: password),
    );
  }

  /// Returns false if the project requires email confirmation.
  Future<bool> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final validationError = passwordValidationError(password);
    if (validationError != null) throw AuthException(validationError);
    _requireSupabaseConfiguration();
    await _ensureOnlineServicesAvailable();

    final response = await Supabase.instance.client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'name': name.trim()},
    );
    if (response.user == null) {
      throw const AuthException('Account creation did not return a user.');
    }
    if (response.session != null) await _syncAuthUser(response.user!);
    return response.session != null;
  }

  Future<void> signOut() async {
    if (SupabaseConfig.isConfigured) {
      await Supabase.instance.client.auth.signOut();
    }
    _currentUser = null;
    await ThemeService.instance.resetToDefaultGuestTheme();
  }

  /// Opens the local-only workspace without creating a Supabase account.
  Future<void> continueAsGuest() async {
    _currentUser = null;
    await _loadLocalUser();
  }

  Future<void> _ensureOnlineServicesAvailable() async {
    final connection = await Connectivity().checkConnectivity();
    if (connection.isEmpty ||
        connection.every((result) => result == ConnectivityResult.none)) {
      throw const AuthException(
        'No internet connection. Sign-in needs internet. Connect and try again, or continue as a guest.',
      );
    }
    final settings = await Supabase.instance.client
        .from('app_control_settings')
        .select('maintenance_enabled,minimum_supported_version')
        .eq('id', true)
        .maybeSingle()
        .timeout(const Duration(seconds: 8));
    if (settings?['maintenance_enabled'] == true) {
      throw const AuthException(
          'Online services are under maintenance. You can continue in Guest mode.');
    }
    final minimum = settings?['minimum_supported_version']?.toString();
    final installedVersion = await AppVersionService.loadInstalledVersion();
    if (installedVersion == null) {
      throw const AuthException(
        'Could not read this app’s installed version. Restart the app and try again.',
      );
    }
    if (minimum != null &&
        installedVersion != null &&
        AppVersionService.isBelowMinimum(installedVersion, minimum)) {
      throw AuthException(
          'Update required. Install version $minimum or newer to sign in.');
    }
  }

  void _requireSupabaseConfiguration() {
    if (!SupabaseConfig.isConfigured) {
      throw StateError('Supabase is not configured for this build.');
    }
  }

  Future<void> _loadLocalUser() async {
    final userId = await DatabaseHelper.instance.getOrCreateGuestUserId();
    final userData = await DatabaseHelper.instance.getUserById(userId);
    _currentUser = UserModel.fromMap(userData!);
    await ThemeService.instance.loadForUser(_currentUser!.id);
  }

  Future<void> _syncAuthUser(User authUser) async {
    final client = Supabase.instance.client;
    final profileResponse = await client
        .from('profiles')
        .select('account_status')
        .eq('id', authUser.id)
        .maybeSingle();
    if (profileResponse == null) {
      throw const AuthException(
          'Your account profile is not ready yet. Please try again shortly.');
    }
    if (profileResponse['account_status'] != 'active') {
      await client.auth.signOut();
      _currentUser = null;
      throw const AuthException(
          'This account is suspended. Contact the project administrator.');
    }
    final control = await client
        .from('app_control_settings')
        .select('minimum_supported_version')
        .eq('id', true)
        .maybeSingle();
    final minimum = control?['minimum_supported_version']?.toString();
    final installedVersion = AppVersionService.cachedVersion;
    if (minimum != null &&
        installedVersion != null &&
        AppVersionService.isBelowMinimum(installedVersion, minimum)) {
      await client.auth.signOut();
      _currentUser = null;
      throw AuthException(
          'Update required. Install version $minimum or newer to continue.');
    }
    await client.rpc('record_my_login');
    final email = authUser.email;
    if (email == null || email.isEmpty) {
      throw const AuthException(
          'This Supabase account does not have an email address.');
    }
    final metadata = authUser.userMetadata ?? const <String, dynamic>{};
    final suppliedName = metadata['name']?.toString().trim();
    final now = DateTime.now().toIso8601String();
    final existing =
        await DatabaseHelper.instance.getUserBySupabaseId(authUser.id) ??
            await DatabaseHelper.instance.getUserByEmail(email);
    final id = await DatabaseHelper.instance.upsertUser({
      'supabase_user_id': authUser.id,
      'name': suppliedName == null || suppliedName.isEmpty
          ? email.split('@').first
          : suppliedName,
      'email': email,
      'password_hash': 'supabase-managed',
      'role': 'user',
      'status': existing?['status'] as String? ?? 'active',
      'created_at': authUser.createdAt ?? now,
      'updated_at': now,
    });
    final localUser = await DatabaseHelper.instance.getUserById(id);
    _currentUser = UserModel.fromMap(localUser!);
    await ThemeService.instance.loadForUser(_currentUser!.id);
  }

  Future<UserModel> resetGuestProfile() async {
    final user = await requireLocalUser();
    if (user.supabaseUserId != null ||
        user.email != 'guest@convert2file.local') {
      throw StateError('Only the local guest profile can be reset.');
    }
    if (user.profileImagePath != null) {
      final image = File(user.profileImagePath!);
      if (await image.exists()) await image.delete();
    }
    await DatabaseHelper.instance.updateUserProfile(user.id!, {
      'name': 'Guest User',
      'bio': null,
      'phone': null,
      'location': null,
      'profile_image_path': null,
    });
    final data = await DatabaseHelper.instance.getUserById(user.id!);
    _currentUser = UserModel.fromMap(data!);
    return _currentUser!;
  }

  Future<UserModel?> updateProfile({
    String? name,
    String? bio,
    String? phone,
    String? location,
    String? profileImagePath,
    bool clearProfileImage = false,
  }) async {
    final user = await requireLocalUser();
    final values = <String, dynamic>{};
    if (name != null && name.trim().isNotEmpty) values['name'] = name.trim();
    if (bio != null) values['bio'] = bio;
    if (phone != null) values['phone'] = phone;
    if (location != null) values['location'] = location;
    if (clearProfileImage) {
      values['profile_image_path'] = null;
    } else if (profileImagePath != null) {
      values['profile_image_path'] = profileImagePath;
    }

    if (values.isEmpty) return user;

    if (SupabaseConfig.isConfigured &&
        Supabase.instance.client.auth.currentUser != null &&
        values.containsKey('name')) {
      await Supabase.instance.client
          .from('profiles')
          .update({'display_name': values['name']}).eq(
              'id', Supabase.instance.client.auth.currentUser!.id);
    }
    await DatabaseHelper.instance.updateUserProfile(user.id!, values);
    final userData = await DatabaseHelper.instance.getUserById(user.id!);
    if (userData == null) return null;

    _currentUser = UserModel.fromMap(userData);
    await DatabaseHelper.instance.insertLog({
      'user_id': user.id,
      'level': 'info',
      'event_type': 'profile.update',
      'message': 'Local profile updated',
      'context_json': jsonEncode(values.keys.toList()),
      'created_at': DateTime.now().toIso8601String(),
    });

    return _currentUser;
  }
}
