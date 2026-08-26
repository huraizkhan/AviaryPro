import 'package:flutter/material.dart';

import '../screens/splash/splash_screen.dart';
import '../ui/aviary_design.dart';

class AviaryProApp extends StatelessWidget {
  const AviaryProApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AviaryColors.birds,
      brightness: Brightness.light,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Aviary Pro',
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          backgroundColor: Color(0xFFF7F8FA),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 1,
          titleTextStyle: TextStyle(
            color: Color(0xFF20252B),
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0x11000000)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0x22000000)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0x22000000)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: AviaryColors.birds,
              width: 1.6,
            ),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          indicatorColor: AviaryColors.birds.withValues(alpha: .14),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            return TextStyle(
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
            );
          }),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
