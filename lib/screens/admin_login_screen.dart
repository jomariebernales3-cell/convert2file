import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/admin_access.dart';
import '../services/auth_service.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController(text: AdminAccess.email);
  final _password = TextEditingController();
  final _auth = AuthService();
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await _auth.signInAsAdministrator(email: _email.text, password: _password.text);
      if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/admin', (_) => false);
    } on AuthException catch (error) {
      _show(error.message);
    } catch (error) {
      _show(error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String text) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red.shade700, content: Text(text)),
      );

  @override
  Widget build(BuildContext context) {
    const surface = Color(0xFF0F1218);
    const line = Color(0xFF303744);
    const muted = Color(0xFFA7AFBC);
    const cyan = Color(0xFF67E8F9);
    return Scaffold(
      backgroundColor: const Color(0xFF05070B),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: line),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Icon(Icons.admin_panel_settings_outlined, color: cyan, size: 36),
                    const SizedBox(height: 14),
                    const Text('Administrator sign in', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const Text('Restricted to the configured Convert2File administrator account.', textAlign: TextAlign.center, style: TextStyle(color: muted, height: 1.4)),
                    const SizedBox(height: 22),
                    _field(controller: _email, label: 'Administrator email', icon: Icons.mail_outline, keyboard: TextInputType.emailAddress, validator: (value) => AdminAccess.isAdministratorEmail(value ?? '') ? null : 'Use the configured administrator email.'),
                    const SizedBox(height: 14),
                    _field(controller: _password, label: 'Password', icon: Icons.lock_outline, obscure: _obscure, suffix: IconButton(onPressed: () => setState(() => _obscure = !_obscure), icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined)), validator: (value) => value == null || value.length < 6 ? 'Enter your password.' : null),
                    const SizedBox(height: 20),
                    SizedBox(height: 52, child: ElevatedButton(
                      onPressed: _busy || !_auth.isSupabaseConfigured ? null : _submit,
                      style: ElevatedButton.styleFrom(backgroundColor: cyan, foregroundColor: const Color(0xFF05070B), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Sign in as administrator', style: TextStyle(fontWeight: FontWeight.w800)),
                    )),
                    const SizedBox(height: 8),
                    TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Back to user sign in')),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String? Function(String?) validator,
    TextInputType? keyboard,
    bool obscure = false,
    Widget? suffix,
  }) => TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboard,
        obscureText: obscure,
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
