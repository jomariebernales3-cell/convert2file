import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';

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
          _showMessage('Check your email to confirm your account, then sign in.');
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
    if (lower.contains('invalid login credentials')) return 'Incorrect email or password.';
    if (lower.contains('email not confirmed')) return 'Please confirm your email before signing in.';
    if (lower.contains('already registered')) return 'An account already exists for this email.';
    return message;
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: error ? Colors.red.shade700 : null, content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    const surface = Color(0xFF0F1218);
    const line = Color(0xFF303744);
    const muted = Color(0xFFA7AFBC);
    const cyan = Color(0xFF67E8F9);
    final configured = _auth.isSupabaseConfigured;
    return Scaffold(
      backgroundColor: const Color(0xFF05070B),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _isSignUp ? 'Create your account' : 'Welcome back',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isSignUp
                        ? 'Save your Convert2File workspace under your own account.'
                        : 'Sign in to continue to your Convert2File workspace.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: muted, fontSize: 14, height: 1.4),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: line),
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          if (!configured) _configurationNotice(),
                          if (_isSignUp) ...[
                            _field(
                              controller: _nameController,
                              label: 'Full name',
                              icon: Icons.person_outline,
                              validator: (value) => (value == null || value.trim().length < 2) ? 'Enter your name' : null,
                            ),
                            const SizedBox(height: 14),
                          ],
                          _field(
                            controller: _emailController,
                            label: 'Email address',
                            icon: Icons.mail_outline,
                            keyboardType: TextInputType.emailAddress,
                            validator: (value) => (value == null || !value.contains('@')) ? 'Enter a valid email address' : null,
                          ),
                          const SizedBox(height: 14),
                          _field(
                            controller: _passwordController,
                            label: 'Password',
                            icon: Icons.lock_outline,
                            obscureText: _obscurePassword,
                            suffix: IconButton(
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            ),
                            validator: (value) => (value == null || value.length < 6) ? 'Use at least 6 characters' : null,
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _isBusy || !configured ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: cyan,
                                foregroundColor: const Color(0xFF05070B),
                                disabledBackgroundColor: line,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: _isBusy
                                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Text(_isSignUp ? 'Create account' : 'Sign in', style: const TextStyle(fontWeight: FontWeight.w800)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _isBusy ? null : () => setState(() => _isSignUp = !_isSignUp),
                    child: Text(
                      _isSignUp ? 'Already have an account? Sign in' : 'New here? Create an account',
                      style: const TextStyle(color: cyan, fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _isBusy
                        ? null
                        : () => Navigator.of(context).pushNamed('/admin-login'),
                    icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
                    label: const Text('Administrator sign in'),
                    style: TextButton.styleFrom(foregroundColor: muted),
                  ),
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    onPressed: _isBusy ? null : _continueAsGuest,
                    icon: const Icon(Icons.person_outline),
                    label: const Text('Continue as guest'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: muted,
                      side: const BorderSide(color: line),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Convert2File', textAlign: TextAlign.center, style: TextStyle(color: muted, fontWeight: FontWeight.w700)),
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
          color: Colors.amber.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
        ),
        child: const Text(
          'Supabase is not configured in this build. Add SUPABASE_URL and SUPABASE_ANON_KEY to run the login.',
          style: TextStyle(color: Color(0xFFFFD56A), fontSize: 12, height: 1.35),
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
  }) => TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        obscureText: obscureText,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFFA7AFBC)),
          prefixIcon: Icon(icon, color: const Color(0xFFA7AFBC)),
          suffixIcon: suffix,
          filled: true,
          fillColor: const Color(0xFF181D25),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF303744))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF303744))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF67E8F9), width: 1.4)),
        ),
      );
}
