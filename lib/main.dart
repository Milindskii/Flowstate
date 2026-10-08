import 'components/noya_notice.dart';
import 'components/noya_reminder_overlay.dart';
import 'components/edit_task_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/env_config.dart';
import 'providers/app_state_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/flow_provider.dart';
import 'services/api_service.dart';
import 'services/flow_clock.dart';
import 'services/smart_reminder_service.dart';
import 'screens/splash_screen.dart';
import 'theme/flow_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase Auth & Client via EnvConfig
  try {
    await Supabase.initialize(
      url: EnvConfig.supabaseUrl,
      publishableKey: EnvConfig.supabaseAnonKey,
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

  final sharedApi = ApiService();
  final appState = AppStateProvider(customApi: sharedApi);
  final flowProvider = FlowProvider(api: sharedApi, currentUserId: () => appState.currentUser?.id);
  // Signing out wipes the account's progression (balance, Shields, quests): the next account starts from the server.
  appState.onAccountCleared = flowProvider.reset;

  final reminderService = SmartReminderService.instance;
  reminderService.taskListProvider = () => appState.tasks;
  reminderService.onOpenTask = (taskId, targetDate) {
    final navContext = FlowstateApp.navigatorKey.currentContext;
    if (navContext != null) {
      try {
        final state = Provider.of<AppStateProvider>(navContext, listen: false);
        if (targetDate != null) {
          final now = FlowClock.currentTime();
          final isToday = targetDate.year == now.year &&
              targetDate.month == now.month &&
              targetDate.day == now.day;
          if (isToday) {
            state.setNavIndex(0);
          } else {
            state.setNavIndex(2);
            state.loadCalendarDay(DateTime(targetDate.year, targetDate.month, targetDate.day));
          }
        } else {
          state.setNavIndex(0);
        }
        final match = state.tasks.where((t) => t.id == taskId).firstOrNull;
        if (match != null) {
          EditTaskSheet.show(navContext, match);
        }
      } catch (e) {
        debugPrint('Error navigating from reminder: $e');
      }
    }
  };
  reminderService.initialize().catchError((e) {
    debugPrint('Reminder service init notice: $e');
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider.value(value: flowProvider),
      ],
      child: const FlowstateApp(),
    ),
  );
}

class FlowstateApp extends StatelessWidget {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final Widget? home;
  const FlowstateApp({super.key, this.home});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Flowstate',
      debugShowCheckedModeBanner: false,
      themeMode: themeProvider.themeMode,
      theme: FlowTheme.lightTheme(themeProvider.lightAccentColor),
      darkTheme: FlowTheme.darkTheme(themeProvider.darkAccentColor),
      themeAnimationDuration: const Duration(milliseconds: 240),
      themeAnimationCurve: Curves.easeInOut,
      scaffoldMessengerKey: NoyaNoticeCenter.instance.messengerKey,
      home: home ?? const SplashScreen(),
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: NoyaReminderOverlay(),
              ),
            ),
          ],
        );
      },
    );
  }
}
