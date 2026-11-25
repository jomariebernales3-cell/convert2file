import 'package:flutter/material.dart';
import '../widgets/bootstrap_icon.dart';
import '../services/auth_service.dart';
import '../widgets/figma_app_chrome.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _hasLength => _newController.text.length >= 8;
  bool get _hasNumber => RegExp(r'\d').hasMatch(_newController.text);
  bool get _hasUppercase => RegExp(r'[A-Z]').hasMatch(_newController.text);
  bool get _hasSymbol => RegExp(r'[^\w\s]').hasMatch(_newController.text);
  bool get _matches => _newController.text == _confirmController.text;
  bool get _ready =>
      _currentController.text.isNotEmpty &&
      _hasLength &&
      _hasNumber &&
      _hasUppercase &&
      _hasSymbol &&
      _matches;

  Future<void> _updatePassword() async {
    if (!_ready) return;
    setState(() => _busy = true);
    try {
      await AuthService().changePasswordWithCurrent(
        currentPassword: _currentController.text,
        newPassword: _newController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated successfully.')),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: Text('$error'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService().currentUser;
    return FigmaAppShell(
      title: 'Change password',
      subtitle: 'Account security',
      selectedIndex: 2,
      showBack: true,
      showProfile: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (user?.supabaseUserId == null)
              const FigmaCard(
                child: Text(
                    'Password changes are available after signing in to an account.'),
              )
            else ...[
              FigmaCard(
                child: Column(
                  children: [
                    TextField(
                      controller: _currentController,
                      obscureText: true,
                      onChanged: (_) => setState(() {}),
                      decoration:
                          const InputDecoration(labelText: 'Current password'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _newController,
                      obscureText: true,
                      onChanged: (_) => setState(() {}),
                      decoration:
                          const InputDecoration(labelText: 'New password'),
                    ),
                    const SizedBox(height: 12),
                    _rule('At least 8 characters', _hasLength),
                    _rule('One number', _hasNumber),
                    _rule('One uppercase letter', _hasUppercase),
                    _rule('One special character', _hasSymbol),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _confirmController,
                      obscureText: true,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Confirm new password',
                        helperText: _confirmController.text.isEmpty
                            ? null
                            : _matches
                                ? 'Passwords match'
                                : 'Passwords do not match',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy || !_ready ? null : _updatePassword,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Update password'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pushNamed(
                  '/forgot-password',
                  arguments: user?.email,
                ),
                child: const Text('Forgot your password?'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _rule(String label, bool valid) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            BootstrapIcon.material(
                valid ? Icons.check_circle : Icons.circle_outlined,
                size: 17,
                color: valid ? Colors.green : Theme.of(context).hintColor),
            const SizedBox(width: 8),
            Text(label),
          ],
        ),
      );
}
