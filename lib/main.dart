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

  // Set clean system UI overlay (dark icons on light/white background)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
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
  final Widget? home;
  const FlowstateApp({super.key, this.home});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'Flowstate',
      debugShowCheckedModeBanner: false,
      themeMode: themeProvider.themeMode,
      theme: FlowTheme.lightTheme(themeProvider.lightAccentColor),
      darkTheme: FlowTheme.darkTheme(themeProvider.darkAccentColor),
      themeAnimationDuration: const Duration(milliseconds: 240),
      themeAnimationCurve: Curves.easeInOut,
      home: home ?? const SplashScreen(),
    );
  }
}
