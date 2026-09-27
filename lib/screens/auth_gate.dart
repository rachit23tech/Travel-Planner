import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/saved_places_service.dart';
import 'map_screen.dart';
import 'sign_in_screen.dart';

/// The app's real entry point: shows [SignInScreen] until the user signs
/// in or chooses to continue as a guest, then shows [MapScreen] either
/// way - signed-in users get Firestore-synced Home/Work/recents, guests
/// keep the local-only behavior the app always had.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _authService = AuthService();
  final _savedPlacesService = SavedPlacesService();

  bool _continuingAsGuest = false;
  String? _pulledForUid;

  /// Pulls this account's cloud data into the local cache exactly once
  /// per sign-in, not on every rebuild.
  void _maybePullCloudData(User user) {
    if (_pulledForUid == user.uid) return;
    _pulledForUid = user.uid;
    _savedPlacesService.pullFromCloud();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final user = snapshot.data;
        if (user != null) {
          _maybePullCloudData(user);
          return MapScreen(authService: _authService);
        }

        if (_continuingAsGuest) {
          return MapScreen(
            authService: _authService,
            onRequestSignIn: () => setState(() => _continuingAsGuest = false),
          );
        }

        return SignInScreen(
          authService: _authService,
          onContinueAsGuest: () => setState(() => _continuingAsGuest = true),
        );
      },
    );
  }
}
