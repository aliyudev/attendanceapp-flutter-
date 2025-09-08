import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/api.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/face_capture_screen.dart';
import 'screens/face_enrollment_screen.dart';
import 'screens/face_verification_screen.dart';
import 'screens/loading_screen.dart';
import 'screens/login_screen.dart';
import 'screens/password_recovery_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/manage_users_screen.dart';
import 'screens/admin_login_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: ApiConfig.supabaseUrl,
    anonKey: ApiConfig.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      autoRefreshToken: true,
    ),
  );
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ITSky Attendance',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme(),
      initialRoute: '/',
      routes: {
        '/': (context) => const LoadingScreen(),
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignupScreen(),
        '/password-recovery': (context) => const PasswordRecoveryScreen(),
        '/dashboard': (context) => const DashboardScreen(),
        '/admin': (context) => const AdminDashboardScreen(),
        '/admin-login': (context) => const AdminLoginScreen(),
        '/face': (context) => const FaceCaptureScreen(),
        '/face-enroll': (context) => const FaceEnrollmentScreen(),
        '/face-verify': (context) => const FaceVerificationScreen(),
        '/manage-users': (context) => const ManageUsersScreen(),
      },
    );
  }
}
