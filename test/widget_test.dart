import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:travel_planner/screens/sign_in_screen.dart';
import 'package:travel_planner/services/auth_service.dart';

void main() {
  // The full app (TravelPlannerApp -> AuthGate) needs Firebase
  // initialized, which isn't available in the plain widget-test
  // environment without extra platform-channel mocking. SignInScreen
  // itself never touches Firebase during build (only inside its button
  // callbacks), so it's tested directly instead - a meaningful smoke
  // test without pulling in Firebase test scaffolding.
  testWidgets('Sign-in screen shows the Google sign-in and skip actions',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SignInScreen(
          authService: AuthService(),
          onContinueAsGuest: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Skip for now'), findsOneWidget);
  });
}
