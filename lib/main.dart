import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'screens/app.dart';
import 'screens/onboarding_screen.dart';
import 'services/ad_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Start initializing ads and preloading early in the background
  AdService().init();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  await GoogleSignIn.instance.initialize();
  
  final prefs = await SharedPreferences.getInstance();
  OnboardingScreen.skipped.value = prefs.getBool('onboarding_skipped') ?? false;
  
  runApp(const App());
}
