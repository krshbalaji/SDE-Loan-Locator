import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase/firebase_options.dart';
import 'services/auth_service.dart';
import 'services/firestore_loan_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/dashboard/agent_home_screen.dart';
import 'screens/dashboard/master_dashboard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  var firebaseReady = false;
  if (DefaultFirebaseOptions.isConfigured) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      firebaseReady = true;
    } catch (_) {
      firebaseReady = false;
    }
  }

  final repository =
      firebaseReady ? FirestoreLoanService() : InMemoryDemoLoanService();

  runApp(
    LoanLocatorApp(
      useFirebase: firebaseReady,
      repository: repository,
    ),
  );
}

class LoanLocatorApp extends StatelessWidget {
  const LoanLocatorApp({
    super.key,
    required this.useFirebase,
    required this.repository,
  });

  final bool useFirebase;
  final LoanDataRepository repository;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>(
          create: (_) => AuthService(useFirebase: useFirebase)..init(),
        ),
        ChangeNotifierProvider<LoanPortfolioProvider>(
          create: (_) => LoanPortfolioProvider(
            repository: repository,
            isDemoMode: !useFirebase,
          )..refresh(),
        ),
      ],
      child: MaterialApp(
        title: 'Saro Devi Enterprises — Loan Locator',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1E3A8A),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        home: const _AuthGate(),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;
    if (user == null) {
      return const LoginScreen();
    }
    if (user.isAdminOrAbove) {
      return const MasterDashboard();
    }
    return const AgentHomeScreen();
  }
}
