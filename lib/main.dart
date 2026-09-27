import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/auth_gate.dart';
import 'services/offline_maps_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // No FirebaseOptions passed: on Android this is read at build time
  // from android/app/google-services.json via the Google Services
  // Gradle plugin - see the Firebase setup steps in README.md.
  await Firebase.initializeApp();
  // Sets up the on-disk tile cache so the map keeps working offline -
  // see OfflineMapsService for what this enables.
  await OfflineMapsService.initialize();
  runApp(const TravelPlannerApp());
}

/// Brand palette - "Route Teal" + "Trail Coral", a pin resting on a road.
/// Keep this in sync with the brand board in the design artifact.
class BrandColors {
  static const inkTeal = Color(0xFF0E3433);
  static const routeTeal = Color(0xFF1B5E5A);
  static const tealTint = Color(0xFFA9D2C9);
  static const trailCoral = Color(0xFFF2643B);
  static const coralPressed = Color(0xFFD6502A);
  static const cream = Color(0xFFFAF7F1);
  static const nightTeal = Color(0xFF0B2726);
  static const ink = Color(0xFF1A1A17);
  static const muted = Color(0xFF6B6B63);
  static const arrivedGreen = Color(0xFF2F9E5B);
  static const rerouteAmber = Color(0xFFE8A33D);
}

class TravelPlannerApp extends StatelessWidget {
  const TravelPlannerApp({super.key});

  static TextTheme _textTheme(Brightness brightness) {
    final base = brightness == Brightness.dark
        ? Typography.material2021().white
        : Typography.material2021().black;
    final withBody = GoogleFonts.workSansTextTheme(base);
    // Fraunces for the big, expressive numbers and headlines (distance
    // readouts, screen titles); Work Sans everywhere else.
    return withBody.copyWith(
      headlineLarge: GoogleFonts.fraunces(textStyle: withBody.headlineLarge, fontWeight: FontWeight.w600),
      headlineMedium: GoogleFonts.fraunces(textStyle: withBody.headlineMedium, fontWeight: FontWeight.w600),
      headlineSmall: GoogleFonts.fraunces(textStyle: withBody.headlineSmall, fontWeight: FontWeight.w600),
      titleLarge: GoogleFonts.fraunces(textStyle: withBody.titleLarge, fontWeight: FontWeight.w600),
    );
  }

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = isDark
        ? const ColorScheme.dark(
            primary: BrandColors.tealTint,
            onPrimary: BrandColors.inkTeal,
            primaryContainer: BrandColors.routeTeal,
            onPrimaryContainer: BrandColors.cream,
            secondary: BrandColors.trailCoral,
            onSecondary: BrandColors.cream,
            surface: BrandColors.nightTeal,
            onSurface: BrandColors.cream,
            error: BrandColors.coralPressed,
          )
        : const ColorScheme.light(
            primary: BrandColors.routeTeal,
            onPrimary: BrandColors.cream,
            primaryContainer: BrandColors.tealTint,
            onPrimaryContainer: BrandColors.inkTeal,
            secondary: BrandColors.trailCoral,
            onSecondary: BrandColors.cream,
            surface: Colors.white,
            onSurface: BrandColors.ink,
            error: BrandColors.coralPressed,
          );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark ? BrandColors.nightTeal : BrandColors.cream,
      textTheme: _textTheme(brightness),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? BrandColors.nightTeal : BrandColors.cream,
        foregroundColor: isDark ? BrandColors.cream : BrandColors.ink,
        elevation: 0,
        titleTextStyle: GoogleFonts.fraunces(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: isDark ? BrandColors.cream : BrandColors.ink,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 3,
        shadowColor: BrandColors.inkTeal.withValues(alpha: 0.25),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? BrandColors.routeTeal.withValues(alpha: 0.35) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide.none,
        ),
        labelStyle: GoogleFonts.workSans(fontWeight: FontWeight.w600),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: BrandColors.trailCoral,
          foregroundColor: BrandColors.cream,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: BrandColors.trailCoral,
        foregroundColor: BrandColors.cream,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? BrandColors.routeTeal.withValues(alpha: 0.25) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? BrandColors.nightTeal : Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Iter',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const AuthGate(),
    );
  }
}
