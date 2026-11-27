import 'services/maker_checker_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase/firebase_options.dart';
import 'services/activity_telemetry_service.dart';
import 'services/audit_service.dart';
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
        ChangeNotifierProvider<MakerCheckerService>(create: (ctx) => MakerCheckerService(useFirebase: useFirebase, auditService: ctx.read<AuditService>())),
        ChangeNotifierProvider<ActivityTelemetryService>(
          create: (_) => ActivityTelemetryService(useFirebase: useFirebase),
        ),
        ChangeNotifierProvider<AuditService>(
          create: (_) => AuditService(useFirebase: useFirebase),
        ),
        ChangeNotifierProxyProvider<AuditService, AuthService>(
          create: (ctx) => AuthService(useFirebase: useFirebase, auditService: ctx.read<AuditService>())..init(),
          update: (ctx, audit, prev) => prev ?? AuthService(useFirebase: useFirebase, auditService: audit)..init(),
        ),
        ChangeNotifierProvider<LoanPortfolioProvider>(
          create: (_) => LoanPortfolioProvider(
            repository: repository,
            isDemoMode: !useFirebase,
          )..refresh(),
        ),
      ],
      child: Builder(
        builder: (context) => MaterialApp(
          title: 'Saro Devi Enterprises — Loan Locator',
          navigatorObservers: [
            context.read<ActivityTelemetryService>().navigatorObserver,
          ],
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
      ),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  String? _lastSessionKey;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    if (auth.isInitializing) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final demoBlocked = auth.isDemoSession && !auth.demoLoginEnabled;
    final user = demoBlocked ? null : auth.currentUser;
    final sessionKey = user == null
        ? 'SIGNED_OUT'
        : '${user.uid}_${auth.isDemoSession ? "DEMO" : "LIVE"}';

    if (sessionKey != _lastSessionKey) {
      _lastSessionKey = sessionKey;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final telemetry = context.read<ActivityTelemetryService>();
        if (user == null) {
          await telemetry.endSession();
          return;
        }
        telemetry.startSession(user, isDemoSession: auth.isDemoSession);
          if (!mounted) return;
          final portfolio = context.read<LoanPortfolioProvider>();
          if (auth.isDemoSession || !auth.useFirebase) {
            portfolio.switchToDemoSandbox();
          } else {
            portfolio.switchToLiveFirestore();
          }
        
      });
    }

    if (user == null) {
      return const LoginScreen();
    }
    if (user.isAdminOrAbove) {
      return const MasterDashboard();
    }
    return const AgentHomeScreen();
  }
}


