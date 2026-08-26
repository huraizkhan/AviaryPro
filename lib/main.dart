import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/app.dart';
import 'providers/bird_provider.dart';
import 'providers/theme_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BirdProvider()..loadBirds()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()..load()),
      ],
      child: const AviaryProApp(),
    ),
  );
}
