import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/activity_telemetry_service.dart';

import '../../services/auth_service.dart';
import '../../services/firestore_loan_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController(text: 'balaji@sde-finance.in');
  final _passwordController = TextEditingController(text: 'demo1234');
  bool _obscure = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final auth = context.read<AuthService>();
    final telemetry = context.read<ActivityTelemetryService>();
    final ok = await auth.signInWithEmailPassword(
      _emailController.text,
      _passwordController.text,
    );
    if (ok) {
      telemetry.logFeatureReviewed(
        'Signed In With Credentials',
        detail: _emailController.text.trim(),
      );
    }
    if (!mounted) return;
    if (!ok && auth.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.errorMessage!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.account_balance,
                      size: 48,
                      color: scheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Saro Devi Enterprises',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: scheme.primary,
                          ),
                    ),
                    Text(
                      'Special Finance Unit — Loan Locator & Collections',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 20),
                    if (!auth.useFirebase)
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 18, color: Colors.amber),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Demo Mode active (Firebase keys not yet configured). Sign in below or pick a role.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Officer Email',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility : Icons.visibility_off,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: auth.isLoading
                            ? null
                            : () async {
                                final messenger = ScaffoldMessenger.of(context);
                                final msg = await auth.sendPasswordReset(
                                  _emailController.text,
                                );
                                messenger.showSnackBar(
                                  SnackBar(content: Text(msg)),
                                );
                              },
                        child: const Text('Forgot Password?'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: auth.isLoading ? null : _handleLogin,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: auth.isLoading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Sign In'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (auth.demoLoginEnabled || !auth.useFirebase)
                      OutlinedButton.icon(
                        onPressed: auth.isLoading
                            ? null
                            : () async {
                                final portfolio = context.read<LoanPortfolioProvider>();
                                await auth.switchToDemoSandbox();
                                if (auth.isDemoSession) {
                                  await portfolio.switchToDemoSandbox();
                                }
                              },
                        icon: const Icon(Icons.play_circle_outline),
                        label: const Text('Demo Check-In (Tester Sandbox)'),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Demo Sandbox disabled by Super Admin. Sign in with your official email.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ),
                    if (!auth.useFirebase) ...[
                      const Divider(height: 28),
                      Text(
                        'Quick Role Access (RBAC Preview)',
                        style: Theme.of(context).textTheme.labelLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          for (final user in AuthService.demoUsers)
                            ActionChip(
                              avatar: Icon(
                                user.isExecutive
                                    ? Icons.shield
                                    : user.isAdminOrAbove
                                        ? Icons.admin_panel_settings
                                        : Icons.location_on,
                                size: 16,
                              ),
                              label: Text(user.displayName.split(' (').first),
                              onPressed: () { context.read<LoanPortfolioProvider>().switchToDemoSandbox(); context.read<ActivityTelemetryService>().logFeatureReviewed('Entered Demo Sandbox', detail: user.role.name); auth.signInAsDemoUser(user); },
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}














