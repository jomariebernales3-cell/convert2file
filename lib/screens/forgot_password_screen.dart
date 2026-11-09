import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});
  final String? initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _auth = AuthService();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _emailFocus = FocusNode();
  final _codeFocus = FocusNode();
  final _passwordFocus = FocusNode();
  int _step = 0;
  int _resendSeconds = 0;
  bool _busy = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  String? _message;
  bool _messageIsError = false;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail ?? '';
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _emailFocus.dispose();
    _codeFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  bool get _validEmail => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
      .hasMatch(_emailController.text.trim());

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  void _setMessage(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = error;
    });
  }

  String _errorMessage(Object error, {required String stage}) {
    final text = error.toString().toLowerCase();
    if (text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('connection refused') ||
        text.contains('clientexception') ||
        text.contains('timed out')) {
      return 'Resetting a password needs an internet connection.';
    }
    if (text.contains('over_email_send_rate_limit') ||
        text.contains('too many requests') ||
        text.contains('rate limit')) {
      return 'Too many requests. Please wait a minute and try again.';
    }
    if (stage == 'code') {
      return 'That code is wrong or has expired. Request a new one.';
    }
    if (stage == 'send') return 'Could not send a reset code. Please try again.';
    return 'Could not update the password. Please try again.';
  }

  Future<void> _sendCode({bool resend = false}) async {
    if (!_validEmail) {
      _setMessage('Enter a valid email address.', error: true);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _auth.sendPasswordRecoveryCode(email: _emailController.text);
      if (!mounted) return;
      setState(() {
        _step = 1;
        _busy = false;
      });
      _setMessage('If an account exists for that email, we sent a code.');
      _startResendTimer();
      if (!resend) _codeFocus.requestFocus();
    } catch (error) {
      _setMessage(_errorMessage(error, stage: 'send'), error: true);
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6,8}$').hasMatch(code)) {
      _setMessage('Enter the 6 to 8 digit code.', error: true);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _auth.verifyPasswordRecoveryCode(
        email: _emailController.text,
        code: code,
      );
      if (!mounted) return;
      setState(() {
        _step = 2;
        _busy = false;
      });
      _passwordFocus.requestFocus();
    } catch (error) {
      _setMessage(_errorMessage(error, stage: 'code'), error: true);
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<void> _updatePassword() async {
    final password = _passwordController.text;
    if (password.length < 6) {
      _setMessage('Use at least 6 characters for your password.', error: true);
      return;
    }
    if (password != _confirmController.text) {
      _setMessage('The passwords do not match.', error: true);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _auth.updatePassword(password: password);
      await _auth.signOut();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      _setMessage(_errorMessage(error, stage: 'update'), error: true);
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  void _goBackStep() {
    if (_busy) return;
    if (_step > 0) {
      setState(() {
        _step--;
        _message = null;
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<bool> _handleSystemBack() async {
    if (_step > 0) {
      _goBackStep();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = switch (_step) {
      0 => 'Forgot password?',
      1 => 'Enter the code',
      _ => 'Set a new password',
    };
    final subtitle = switch (_step) {
      0 => "Enter your email and we'll send you a code.",
      1 => 'We sent a code to ${_emailController.text.trim()}.',
      _ => 'Choose a new password for your account.',
    };

    return WillPopScope(
      onWillPop: _handleSystemBack,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 390),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: IconButton(
                        tooltip: 'Back',
                        onPressed: _busy ? null : _goBackStep,
                        style: IconButton.styleFrom(
                          backgroundColor: colors.surfaceContainerHighest,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: Icon(Icons.arrow_back, color: colors.onSurface),
                      ),
                    ),
                    const SizedBox(height: 26),
                    Text(
                      title,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 28,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(subtitle, style: TextStyle(color: theme.hintColor, height: 1.5)),
                    const SizedBox(height: 24),
                    if (_step == 0) _emailStep(),
                    if (_step == 1) _codeStep(),
                    if (_step == 2) _passwordStep(),
                    if (_message != null) ...[
                      const SizedBox(height: 14),
                      _messageCard(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emailStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _input(
            controller: _emailController,
            focusNode: _emailFocus,
            label: 'Email address',
            icon: Icons.mail_outline,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 18),
          _primaryButton('Send code', _sendCode),
        ],
      );

  Widget _codeStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _input(
            controller: _codeController,
            focusNode: _codeFocus,
            label: 'Verification code',
            icon: Icons.pin_outlined,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
            ],
            textAlign: TextAlign.center,
            letterSpacing: 8,
          ),
          const SizedBox(height: 18),
          _primaryButton('Verify code', _verifyCode),
          Center(
            child: TextButton(
              onPressed: _busy || _resendSeconds > 0
                  ? null
                  : () => _sendCode(resend: true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
                minimumSize: const Size(44, 44),
              ),
              child: Text(_resendSeconds > 0
                  ? 'Resend in ${_resendSeconds}s'
                  : 'Resend code'),
            ),
          ),
          Center(
            child: TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      _resendTimer?.cancel();
                      setState(() {
                        _step = 0;
                        _message = null;
                        _codeController.clear();
                      });
                    },
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
                minimumSize: const Size(44, 44),
              ),
              child: const Text('Use a different email'),
            ),
          ),
        ],
      );

  Widget _passwordStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _input(
            controller: _passwordController,
            label: 'New password',
            icon: Icons.lock_outline,
            obscureText: !_showPassword,
            suffix: IconButton(
              onPressed: () => setState(() => _showPassword = !_showPassword),
              icon: Icon(_showPassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined),
            ),
          ),
          const SizedBox(height: 12),
          _input(
            controller: _confirmController,
            label: 'Confirm password',
            icon: Icons.lock_outline,
            obscureText: !_showConfirmPassword,
            suffix: IconButton(
              onPressed: () => setState(
                  () => _showConfirmPassword = !_showConfirmPassword),
              icon: Icon(_showConfirmPassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined),
            ),
          ),
          const SizedBox(height: 18),
          _primaryButton('Update password', _updatePassword),
        ],
      );

  Widget _input({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    FocusNode? focusNode,
    TextInputType? keyboardType,
    List<String>? autofillHints,
    List<TextInputFormatter>? inputFormatters,
    bool obscureText = false,
    TextAlign textAlign = TextAlign.start,
    double letterSpacing = 0,
    Widget? suffix,
    ValueChanged<String>? onChanged,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SizedBox(
      height: 56,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        autofillHints: autofillHints,
        inputFormatters: inputFormatters,
        obscureText: obscureText,
        textAlign: textAlign,
        onChanged: onChanged,
        style: TextStyle(color: colors.onSurface, letterSpacing: letterSpacing),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: colors.onSurfaceVariant),
          suffixIcon: suffix,
          filled: true,
          fillColor: colors.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colors.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colors.primary, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
    );
  }

  Widget _primaryButton(String label, Future<void> Function() onPressed) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _busy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          disabledBackgroundColor: colors.primary.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: _busy
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.onPrimary,
                ),
              )
            : Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _messageCard() {
    final colors = Theme.of(context).colorScheme;
    final background = _messageIsError
        ? colors.errorContainer
        : colors.secondaryContainer;
    final foreground = _messageIsError
        ? colors.onErrorContainer
        : colors.onSecondaryContainer;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(_message!, style: TextStyle(color: foreground)),
    );
  }
}