import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _auth = AuthService();
  bool _isSignUp = false;
  bool _isBusy = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isBusy = true);
    try {
      if (_isSignUp) {
        final signedIn = await _auth.signUp(
          name: _nameController.text,
          email: _emailController.text,
          password: _passwordController.text,
        );
        if (!mounted) return;
        if (!signedIn) {
          _showMessage(
              'Check your email to confirm your account, then sign in.');
          setState(() => _isSignUp = false);
          return;
        }
      } else {
        await _auth.signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );
      }
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
      }
    } on AuthException catch (error) {
      if (error.message.toLowerCase().contains('email not confirmed')) {
        _showEmailConfirmationMessage();
      } else {
        _showMessage(_friendlyAuthMessage(error.message), error: true);
      }
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Bad state: ', ''),
          error: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _showEmailConfirmationMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Theme.of(context).colorScheme.errorContainer,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Please confirm your email before signing in.',
              style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
            ),
            TextButton(
              onPressed: _isBusy ? null : _resendConfirmationEmail,
              child: const Text('Resend confirmation email'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resendConfirmationEmail() async {
    setState(() => _isBusy = true);
    try {
      await _auth.resendConfirmationEmail(email: _emailController.text);
      _showMessage('Check your inbox and spam folder, then sign in again.');
    } on AuthException catch (error) {
      _showMessage(_friendlyAuthMessage(error.message), error: true);
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Bad state: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }
  Future<void> _continueAsGuest() async {
    setState(() => _isBusy = true);
    try {
      await _auth.continueAsGuest();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
      }
    } catch (error) {
      _showMessage('Could not open guest workspace: $error', error: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  String _friendlyAuthMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('invalid login credentials'))
      return 'Incorrect email or password.';
    if (lower.contains('email not confirmed'))
      return 'Please confirm your email before signing in.';
    if (lower.contains('already registered'))
      return 'An account already exists for this email.';
    return message;
  }

  void _showPasswordUpdatedMessage() {
    final appColors = AppColors.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: appColors.accent,
        content: Text(
          'Password updated. Sign in with your new password.',
          style: TextStyle(color: appColors.accentInk),
        ),
      ),
    );
  }
  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          backgroundColor: error ? Theme.of(context).colorScheme.errorContainer : null,
          content: Text(
            message,
            style: error
                ? TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)
                : null,
          )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final configured = _auth.isSupabaseConfigured;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 390),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                      _isSignUp ? 'Create your account' : 'Welcome back',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 28,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _isSignUp
                        ? 'Keep your study materials and settings on this device.'
                        : 'Sign in to continue to your Convert2File workspace.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.hintColor,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        if (!configured) _configurationNotice(),
                        if (_isSignUp) ...[
                          _field(
                            controller: _nameController,
                            label: 'Full name',
                            icon: Icons.person_outline,
                            validator: (value) =>
                                (value == null || value.trim().length < 2)
                                    ? 'Enter your name'
                                    : null,
                          ),
                          const SizedBox(height: 12),
                        ],
                        _field(
                          controller: _emailController,
                          label: 'Email address',
                          icon: Icons.mail_outline,
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) =>
                              (value == null || !value.contains('@'))
                                  ? 'Enter a valid email address'
                                  : null,
                        ),
                        const SizedBox(height: 12),
                        _field(
                          controller: _passwordController,
                          label: 'Password',
                          icon: Icons.lock_outline,
                          obscureText: _obscurePassword,
                          suffix: IconButton(
                            style: IconButton.styleFrom(foregroundColor: theme.hintColor),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                          validator: (value) =>
                              (value == null || value.length < 6)
                                  ? 'Use at least 6 characters'
                                  : null,
                        ),
                        ),
                        if (!_isSignUp)
                          Align(
                            alignment: Alignment.centerRight,
                            child: SizedBox(
                              height: 48,
                              child: TextButton(
                                onPressed: _isBusy || !configured
                                    ? null
                                    : () async {
                                        final email = _emailController.text.trim();
                                        final validEmail = RegExp(
                                          r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                                        ).hasMatch(email);
                                        final updated = await Navigator.of(context)
                                            .pushNamed<bool>(
                                          '/forgot-password',
                                          arguments: validEmail ? email : null,
                                        );
                                        if (updated == true && mounted) {
                                          _showPasswordUpdatedMessage();
                                        }
                                      },
                                style: TextButton.styleFrom(
                                  foregroundColor: colors.primary,
                                  minimumSize: const Size(44, 44),
                                ),
                                child: const Text('Forgot password?'),
                              ),
                            ),
                          ),
                        const SizedBox(height: 18),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _isBusy || !configured ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.primary,
                              foregroundColor: colors.onPrimary,
                              disabledBackgroundColor:
                                  theme.disabledColor.withValues(alpha: 0.15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _isBusy
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    _isSignUp ? 'Create account' : 'Sign in',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(child: Divider(color: theme.dividerColor)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'or',
                          style: TextStyle(color: theme.hintColor),
                        ),
                      ),
                      Expanded(child: Divider(color: theme.dividerColor)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: _isBusy ? null : _continueAsGuest,
                      icon: const Icon(Icons.person_outline),
                      label: const Text('Continue as guest'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.primary,
                        side: BorderSide(color: colors.primary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _isBusy
                        ? null
                        : () => setState(() => _isSignUp = !_isSignUp),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.primary,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Center(
                      child: Text(
                        _isSignUp
                            ? 'Already have an account? Sign in'
                            : 'New here? Create an account',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      'Convert2File',
                      style: TextStyle(
                        color: theme.hintColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _configurationNotice() => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Text(
          'Supabase is not configured in this build. Add SUPABASE_URL and SUPABASE_ANON_KEY to run the login.',
          style:
              TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, height: 1.35),
        ),
      );

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffix,
  }) =>
      TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        obscureText: obscureText,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        decoration: InputDecoration(
          hintText: label,
          hintStyle: TextStyle(color: Theme.of(context).hintColor),
          prefixIcon: Icon(icon, color: Theme.of(context).hintColor),
          suffixIcon: suffix,
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Theme.of(context).dividerColor)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Theme.of(context).dividerColor)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary, width: 1.4)),
        ),
      );
}
