import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../widgets/report_problem_entry.dart';
import 'forgot_password_screen.dart';

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
  String? _formError;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      setState(() => _formError = null);
      return;
    }
    setState(() {
      _isBusy = true;
      _formError = null;
    });
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
      setState(() => _formError = _friendlyAuthMessage(error.message));
      if (error.message.toLowerCase().contains('email not confirmed')) {
        _showEmailConfirmationMessage();
      } else {
        _showMessage(_friendlyAuthMessage(error.message), error: true);
      }
    } catch (error) {
      setState(() => _formError = error.toString().replaceFirst('Bad state: ', ''));
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

  void _clearFormError(String _) {
    if (_formError != null) setState(() => _formError = null);
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
      resizeToAvoidBottomInset: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight > 48 ? constraints.maxHeight - 48 : 0.0,
              ),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _isSignUp ? 'Create your account' : 'Welcome back',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: colors.onSurface,
                                  fontSize: 29,
                                  height: 1.15,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _isSignUp
                                    ? 'Keep your study materials and settings on this device.'
                                    : 'Sign in to continue to your Convert2File workspace.',
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 28),
                              Form(
                                key: _formKey,
                                autovalidateMode: AutovalidateMode.onUserInteraction,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    if (!configured) _configurationNotice(),
                                    if (_isSignUp) ...[
                                      _field(
                                        controller: _nameController,
                                        label: 'Full name',
                                        icon: Icons.person_outline,
                                        autofillHints: const [AutofillHints.name],
                                        enabled: !_isBusy,
                                        onChanged: _clearFormError,
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
                                      textInputAction: TextInputAction.next,
                                      autofillHints: const [AutofillHints.email],
                                      enabled: !_isBusy,
                                      onChanged: _clearFormError,
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
                                      textInputAction: TextInputAction.done,
                                      autofillHints: const [AutofillHints.password],
                                      enabled: !_isBusy,
                                      onChanged: _clearFormError,
                                      onFieldSubmitted: (_) => _submit(),
                                      suffix: IconButton(
                                        tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                                        style: IconButton.styleFrom(
                                          foregroundColor: colors.onSurfaceVariant,
                                          minimumSize: const Size(48, 48),
                                        ),
                                        onPressed: _isBusy
                                            ? null
                                            : () => setState(() => _obscurePassword = !_obscurePassword),
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
                                    if (!_isSignUp) ...[
                                      const SizedBox(height: 8),
                                      Center(
                                        child: SizedBox(
                                          height: 48,
                                          child: TextButton(
                                            onPressed: _isBusy
                                                ? null
                                                : () async {
                                                    FocusScope.of(context).unfocus();
                                                    final email = _emailController.text.trim();
                                                    final validEmail = RegExp(
                                                      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                                                    ).hasMatch(email);
                                                    try {
                                                      final updated = await Navigator.of(
                                                        context,
                                                        rootNavigator: true,
                                                      ).push<bool>(
                                                        MaterialPageRoute<bool>(
                                                          builder: (_) => ForgotPasswordScreen(
                                                            initialEmail: validEmail ? email : null,
                                                          ),
                                                        ),
                                                      );
                                                      if (updated == true && mounted) {
                                                        _showPasswordUpdatedMessage();
                                                      }
                                                    } catch (_) {
                                                      if (mounted) {
                                                        setState(() => _formError =
                                                            'Could not open password reset. Please try again.');
                                                      }
                                                    }
                                                  },
                                            style: TextButton.styleFrom(
                                              foregroundColor: colors.onSurfaceVariant,
                                              minimumSize: const Size(48, 48),
                                              textStyle: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            child: const Text('Forgot password?'),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                    ] else
                                      const SizedBox(height: 16),
                                    if (_formError != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        _formError!,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: colors.error,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                    SizedBox(
                                      width: double.infinity,
                                      height: 56,
                                      child: ElevatedButton(
                                        onPressed: _isBusy || !configured ? null : _submit,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: colors.primary,
                                          foregroundColor: colors.onPrimary,
                                          disabledBackgroundColor: colors.primary.withValues(alpha: 0.5),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                          textStyle: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        child: _isBusy
                                            ? Semantics(
                                                label: 'Signing in',
                                                liveRegion: true,
                                                child: SizedBox(
                                                  width: 22,
                                                  height: 22,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: colors.onPrimary,
                                                  ),
                                                ),
                                              )
                                            : Text(_isSignUp ? 'Create account' : 'Sign in'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(child: Divider(color: colors.outlineVariant)),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    child: Text(
                                      'or',
                                      style: TextStyle(color: colors.onSurfaceVariant),
                                    ),
                                  ),
                                  Expanded(child: Divider(color: colors.outlineVariant)),
                                ],
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: OutlinedButton.icon(
                                  onPressed: _isBusy ? null : _continueAsGuest,
                                  icon: const Icon(Icons.person_outline),
                                  label: const Text('Continue as guest'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: colors.primary,
                                    side: BorderSide(color: colors.outline),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                height: 48,
                                child: TextButton(
                                  onPressed: _isBusy
                                      ? null
                                      : () {
                                          setState(() {
                                            _isSignUp = !_isSignUp;
                                            _formError = null;
                                            _formKey.currentState?.reset();
                                          });
                                        },
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48),
                                    padding: EdgeInsets.zero,
                                  ),
                                  child: Text.rich(
                                    TextSpan(
                                      style: TextStyle(
                                        color: colors.onSurfaceVariant,
                                        fontSize: 14,
                                      ),
                                      children: [
                                        TextSpan(text: _isSignUp ? 'Already have an account? ' : 'New here? '),
                                        TextSpan(
                                          text: _isSignUp ? 'Sign in' : 'Create an account',
                                          style: TextStyle(
                                            color: colors.primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    ReportProblemEntry(area: 'login', label: 'Having trouble signing in?', contextInfo: {'error_shown': _formError == null ? null : _formError!.substring(0, _formError!.length > 500 ? 500 : _formError!.length)}),
                    Center(
                      child: Text(
                        'Convert2File',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
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
    TextInputAction? textInputAction,
    Iterable<String>? autofillHints,
    bool obscureText = false,
    bool enabled = true,
    Widget? suffix,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onFieldSubmitted,
  }) =>
      TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        autofillHints: autofillHints,
        obscureText: obscureText,
        enabled: enabled,
        onChanged: onChanged,
        onFieldSubmitted: onFieldSubmitted,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        decoration: InputDecoration(
          hintText: label,
          hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          prefixIcon: Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
          suffixIcon: suffix,
          filled: true,
          fillColor: Theme.of(context).colorScheme.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          errorStyle: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.error, width: 2),
          ),
        ),
      );
}
