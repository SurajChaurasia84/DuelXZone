import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../firebase_options.dart';
import 'battles_screen.dart';
import 'coins_screen.dart';
import 'home_screen.dart';
import 'navigation_controller.dart';
import 'onboarding_screen.dart';
import 'profile_screen.dart';
import 'screen_constants.dart';
import 'status_screen.dart';
import 'system_ui.dart';
import 'theme_controller.dart';
import '../services/notification_service.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  int _gateVersion = 0;

  void _refreshGate() => setState(() => _gateVersion++);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppThemeController.themeMode,
      builder: (context, themeMode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          home: _SplashGate(
            child: _BootstrapGate(
              key: ValueKey(_gateVersion),
              onOnboardingComplete: _refreshGate,
            ),
          ),
        );
      },
    );
  }

  ThemeData _theme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final background = isDark ? darkBackground : lightBackground;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: brightness,
      ).copyWith(primary: primaryColor, surface: background),
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: isDark ? Colors.white : Colors.black,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: systemOverlayStyle(background),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? cardBackground : Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: primaryColor, width: 1.4),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: primaryColor,
        unselectedItemColor: isDark ? Colors.white70 : Colors.black54,
        backgroundColor: background,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _FastFadePageTransitionsBuilder(),
          TargetPlatform.iOS: _FastFadePageTransitionsBuilder(),
          TargetPlatform.linux: _FastFadePageTransitionsBuilder(),
          TargetPlatform.macOS: _FastFadePageTransitionsBuilder(),
          TargetPlatform.windows: _FastFadePageTransitionsBuilder(),
        },
      ),
    );
  }
}

class _FastFadePageTransitionsBuilder extends PageTransitionsBuilder {
  const _FastFadePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
      ),
      child: child,
    );
  }
}

class _SplashGate extends StatefulWidget {
  const _SplashGate({required this.child});

  final Widget child;

  @override
  State<_SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<_SplashGate> {
  bool _showSplash = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1150), () {
      if (mounted) {
        setState(() => _showSplash = false);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _showSplash ? const _SplashScreen() : widget.child,
    );
  }
}

class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? darkBackground : lightBackground;
    final softBackground = isDark ? const Color(0xFF1A130F) : const Color(0xFFFFF2EC);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemOverlayStyle(background),
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [background, softBackground],
            ),
          ),
          child: Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final pulse = 0.92 + (_controller.value * 0.12);
                final glow = 18 + (_controller.value * 24);
                final orbit = (_controller.value - 0.5) * 18;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 170,
                      width: 170,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            height: 138,
                            width: 138,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: primaryColor.withValues(alpha: 0.18),
                                width: 1.2,
                              ),
                            ),
                          ),
                          Transform.translate(
                            offset: Offset(-34, -orbit),
                            child: Container(
                              height: 10,
                              width: 10,
                              decoration: const BoxDecoration(
                                color: primaryColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          Transform.translate(
                            offset: Offset(34, orbit),
                            child: Container(
                              height: 8,
                              width: 8,
                              decoration: BoxDecoration(
                                color: primaryColor.withValues(alpha: 0.7),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          Transform.scale(
                            scale: pulse,
                            child: Container(
                              height: 108,
                              width: 108,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(30),
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFFF6A38), primaryColor],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0x66FF4B11),
                                    blurRadius: glow,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Image.asset('assets/icon.png'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'DuelXZone',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _BootstrapGate extends StatelessWidget {
  const _BootstrapGate({super.key, required this.onOnboardingComplete});

  final VoidCallback onOnboardingComplete;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FirebaseApp>(
      future: Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const StatusScreen(
            title: 'Loading DuelXZone',
            subtitle: 'Preparing your arena...',
            loading: true,
          );
        }
        if (snapshot.hasError) {
          return const StatusScreen(
            title: 'Firebase setup required',
            subtitle: 'Connect Firebase config to continue.',
          );
        }
        return _AuthGate(onOnboardingComplete: onOnboardingComplete);
      },
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate({required this.onOnboardingComplete});

  final VoidCallback onOnboardingComplete;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const StatusScreen(
            title: 'Loading DuelXZone',
            subtitle: 'Preparing your arena...',
            loading: true,
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return OnboardingScreen(onCompleted: onOnboardingComplete);
        }

        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
          builder: (context, docSnapshot) {
            if (docSnapshot.connectionState != ConnectionState.done) {
              return const StatusScreen(
                title: 'Loading DuelXZone',
                subtitle: 'Preparing your arena...',
                loading: true,
              );
            }

            final data = docSnapshot.data?.data();
            if (isProfileComplete(data)) {
              return const AppShell();
            }

            return OnboardingScreen(
              existingUser: user,
              existingData: data,
              onCompleted: onOnboardingComplete,
            );
          },
        );
      },
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  @override
  void initState() {
    super.initState();
    NotificationService.initNotifications();
    AppTabController.currentIndex.addListener(_handleTabChange);
  }

  @override
  void dispose() {
    AppTabController.currentIndex.removeListener(_handleTabChange);
    super.dispose();
  }

  void _handleTabChange() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = AppTabController.currentIndex.value;
    final screens = [
      const HomeScreen(),
      const BattlesScreen(),
      const CoinsScreen(),
      const ProfileScreen(),
    ];
    final background = Theme.of(context).scaffoldBackgroundColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemOverlayStyle(background),
      child: PopScope(
        canPop: currentIndex == 0,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (currentIndex != 0) {
            AppTabController.goTo(0);
          }
        },
        child: Scaffold(
          body: IndexedStack(index: currentIndex, children: screens),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: background,
            border: Border(
              top: BorderSide(
                color: primaryColor.withValues(alpha: isDark ? 0.32 : 0.18),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.32)
                    : primaryColor.withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: BottomNavigationBar(
            currentIndex: currentIndex,
            onTap: AppTabController.goTo,
            items: [
              BottomNavigationBarItem(
                icon: const Icon(Icons.home_outlined),
                activeIcon: _tabGlowIcon(Icons.home),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.sports_mma_outlined),
                activeIcon: _tabGlowIcon(Icons.sports_mma),
                label: 'Battles',
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.monetization_on_outlined),
                activeIcon: _tabGlowIcon(Icons.monetization_on),
                label: 'Coins',
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.person_outline),
                activeIcon: _tabGlowIcon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _tabGlowIcon(IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.34),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55FF4B11),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Icon(icon, color: primaryColor),
    );
  }
}
