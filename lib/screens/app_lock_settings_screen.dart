import 'package:flutter/material.dart';
import '../services/app_lock_service.dart';
import '../widgets/figma_app_chrome.dart';

class AppLockSettingsScreen extends StatefulWidget {
  const AppLockSettingsScreen({super.key});

  @override
  State<AppLockSettingsScreen> createState() => _AppLockSettingsScreenState();
}

class _AppLockSettingsScreenState extends State<AppLockSettingsScreen> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;
  bool get _enabling => !AppLockService.instance.isEnabled;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_enabling) {
        if (!RegExp(r'^\d{6}$').hasMatch(_pin.text)) {
          setState(() => _error = 'Enter a six-digit PIN.');
          return;
        }
        if (_pin.text != _confirm.text) {
          setState(() => _error = 'The PINs do not match.');
          return;
        }
        await AppLockService.instance.enable(_pin.text);
      } else if (!await AppLockService.instance.disable(_pin.text)) {
        setState(() => _error = 'Incorrect PIN.');
        return;
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FigmaAppShell(
        title: 'App lock',
        subtitle: 'Local device protection',
        selectedIndex: 2,
        showBack: true,
        showProfile: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: FigmaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_enabling
                    ? 'Choose a six-digit PIN to protect this app on this device.'
                    : 'Enter your PIN to turn off app lock.'),
                const SizedBox(height: 16),
                TextField(
                  controller: _pin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: _enabling ? 'New PIN' : 'PIN',
                    errorText: _error,
                  ),
                ),
                if (_enabling)
                  TextField(
                    controller: _confirm,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(labelText: 'Confirm PIN'),
                  ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child:
                      Text(_enabling ? 'Enable app lock' : 'Disable app lock'),
                ),
              ],
            ),
          ),
        ),
      );
}
