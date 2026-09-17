import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'providers/app_state_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/splash_screen.dart';
import 'theme/flow_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase Auth & Client
  try {
    await Supabase.initialize(
      url: 'https://drfjprhnynktjkiplbzy.supabase.co',
      publishableKey: 'sb_publishable_LDiD72aRDOVKMwD5AMoU5Q_oNntJRrv',
    );
  } catch (e) {
    // Offline or hot-reload safety fallback
    debugPrint('Supabase init notice: $e');
  }

  // Set immersive dark status bar navigation styling
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF111722),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppStateProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const FlowstateApp(),
    ),
  );
}

class FlowstateApp extends StatelessWidget {
  const FlowstateApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'Flowstate',
      debugShowCheckedModeBanner: false,
      themeMode: themeProvider.themeMode,
      theme: FlowTheme.lightTheme,
      darkTheme: FlowTheme.darkTheme,
      home: const SplashScreen(),
    );
  }
}
