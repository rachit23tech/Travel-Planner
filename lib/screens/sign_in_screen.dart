import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// The app's entry screen when nobody is signed in: a single "Continue
/// with Google" action, or "Skip for now" to fall back to local-only
/// storage (the app worked this way before Firebase existed, and still
/// fully does).
class SignInScreen extends StatefulWidget {
  final AuthService authService;
  final VoidCallback onContinueAsGuest;

  const SignInScreen({
    super.key,
    required this.authService,
    required this.onContinueAsGuest,
  });

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _signingIn = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _signingIn = true;
      _error = null;
    });
    try {
      await widget.authService.signInWithGoogle();
      // On success, AuthGate's authStateChanges listener swaps this
      // screen out for the map automatically - nothing more to do here.
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/icon/app_icon.png', width: 96, height: 96),
              const SizedBox(height: 20),
              Text('Iter', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 6),
              Text(
                'Get there, and everything along the way.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sign in to sync your Home, Work, and recent searches across devices.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _signingIn ? null : _signIn,
                  icon: _signingIn
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: const Text('Continue with Google'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _signingIn ? null : widget.onContinueAsGuest,
                child: const Text('Skip for now'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
