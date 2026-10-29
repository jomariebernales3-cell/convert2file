import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/database_helper.dart';
import '../models/user_model.dart';
import 'admin_access.dart';
import 'supabase_config.dart';
import 'theme_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;

  bool get isLoggedIn => _currentUser != null &&
      SupabaseConfig.isConfigured &&
      Supabase.instance.client.auth.currentSession != null;
  bool get isAdmin => _currentUser?.isAdmin ?? false;
  bool get isSupabaseConfigured => SupabaseConfig.isConfigured;

  Future<void> init() async {
    if (!SupabaseConfig.isConfigured) return;
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
    if (AdminAccess.isAdministratorEmail(email)) {
      throw const AuthException(
        'This is an administrator account. Use Administrator sign in.',
      );
    }
    final response = await Supabase.instance.client.auth.signInWithPassword(
      email: email.trim(), password: password,
    );
    if (response.user == null) {
      throw const AuthException('Sign-in did not return a user.');
    }
    await _syncAuthUser(response.user!);
  }

  Future<void> signInAsAdministrator({
    required String email,
    required String password,
  }) async {
    _requireSupabaseConfiguration();
    if (!AdminAccess.isAdministratorEmail(email)) {
      throw const AuthException('This account is not authorized for administrator access.');
    }
    final response = await Supabase.instance.client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    if (response.user == null) {
      throw const AuthException('Sign-in did not return an administrator account.');
    }
    await _syncAuthUser(response.user!);
  }

  /// Returns false if the project requires email confirmation.
  Future<bool> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    _requireSupabaseConfiguration();
    if (AdminAccess.isAdministratorEmail(email)) {
      throw const AuthException('Administrator accounts cannot be created from the user sign-up page.');
    }
    final response = await Supabase.instance.client.auth.signUp(
      email: email.trim(), password: password, data: {'name': name.trim()},
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
    final email = authUser.email;
    if (email == null || email.isEmpty) {
      throw const AuthException('This Supabase account does not have an email address.');
    }
    final metadata = authUser.userMetadata ?? const <String, dynamic>{};
    final suppliedName = metadata['name']?.toString().trim();
    final now = DateTime.now().toIso8601String();
    final existing = await DatabaseHelper.instance.getUserBySupabaseId(authUser.id) ??
        await DatabaseHelper.instance.getUserByEmail(email);
    final id = await DatabaseHelper.instance.upsertUser({
      'supabase_user_id': authUser.id,
      'name': suppliedName == null || suppliedName.isEmpty
          ? email.split('@').first
          : suppliedName,
      'email': email,
      'password_hash': 'supabase-managed',
      // This app grants local administrator access to the one configured
      // Supabase administrator identity only.
      'role': AdminAccess.isAdministratorEmail(email) ? 'admin' : 'user',
      'status': existing?['status'] as String? ?? 'active',
      'created_at': authUser.createdAt ?? now,
      'updated_at': now,
    });
    final localUser = await DatabaseHelper.instance.getUserById(id);
    _currentUser = UserModel.fromMap(localUser!);
    await ThemeService.instance.loadForUser(_currentUser!.id);
  }

  Future<UserModel?> updateProfile({
    String? name,
    String? bio,
    String? phone,
    String? location,
    String? profileImagePath,
  }) async {
    final user = await requireLocalUser();
    final values = <String, dynamic>{};
    if (name != null && name.trim().isNotEmpty) values['name'] = name.trim();
    if (bio != null) values['bio'] = bio;
    if (phone != null) values['phone'] = phone;
    if (location != null) values['location'] = location;
    if (profileImagePath != null) {
      values['profile_image_path'] = profileImagePath;
    }

    if (values.isEmpty) return user;

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
