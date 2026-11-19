import 'package:flutter/material.dart';
import '../services/app_lock_service.dart';

class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});
  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  final _lock = AppLockService.instance;
  final _pinController = TextEditingController();
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lock.addListener(_onLockChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lock.removeListener(_onLockChanged);
    _pinController.dispose();
    super.dispose();
  }

  void _onLockChanged() {
    if (mounted) setState(() => _error = null);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _lock.lock();
    }
  }

  Future<void> _unlock() async {
    setState(() => _checking = true);
    final unlocked = await _lock.verify(_pinController.text);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _error = unlocked ? null : 'Incorrect PIN. Try again.';
      if (unlocked) _pinController.clear();
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _lock,
        builder: (context, _) => Stack(
          children: [
            widget.child,
            if (_lock.isLocked)
              Positioned.fill(
                child: Material(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: SafeArea(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 380),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.lock_outline, size: 52),
                              const SizedBox(height: 16),
                              const Text('Convert2File is locked',
                                  style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _pinController,
                                autofocus: true,
                                obscureText: true,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                onSubmitted: (_) => _unlock(),
                                decoration: InputDecoration(
                                  labelText: 'Six-digit PIN',
                                  errorText: _error,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: _checking ? null : _unlock,
                                  child: _checking
                                      ? const CircularProgressIndicator()
                                      : const Text('Unlock'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}
