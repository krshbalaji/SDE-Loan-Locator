import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/user_model.dart';

/// Role-Based Access Control service using Firebase Auth Custom Claims + `users/{uid}`.
/// Automatically supports Demo Mode authentication when Firebase keys are unconfigured.
class AuthService extends ChangeNotifier {
  AuthService({required this.useFirebase});

  final bool useFirebase;

  AppUser? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  AppUser? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  static const List<AppUser> demoUsers = [
    AppUser(
      uid: 'uid_master_balaji',
      email: 'balaji@sde-finance.in',
      displayName: 'A. K. Balaji (Master)',
      role: UserRole.master,
      phone: '+919842100001',
      branch: 'Madurai HQ',
    ),
    AppUser(
      uid: 'uid_admin_meena',
      email: 'meena@sde-finance.in',
      displayName: 'Meena Sundaram (Branch Admin)',
      role: UserRole.admin,
      phone: '+919842100002',
      branch: 'Madurai HQ',
    ),
    AppUser(
      uid: 'uid_agent_karthik',
      email: 'karthik@sde-finance.in',
      displayName: 'Karthik Raja (Field Officer)',
      role: UserRole.agent,
      phone: '+919842100011',
      branch: 'Madurai North',
    ),
    AppUser(
      uid: 'uid_agent_priya',
      email: 'priya@sde-finance.in',
      displayName: 'Priya Selvam (Field Officer)',
      role: UserRole.agent,
      phone: '+919842100012',
      branch: 'Madurai South',
    ),
  ];

  Map<String, String> get knownAgentNames => {
        for (final u in demoUsers) u.uid: u.displayName,
      };

  Future<void> init() async {
    if (!useFirebase) return;
    final fbUser = FirebaseAuth.instance.currentUser;
    if (fbUser != null) {
      _currentUser = await _resolveFirebaseUser(fbUser);
      notifyListeners();
    }
  }

  /// Signs in via Firebase Auth (production) or matches demo persona (demo mode).
  Future<bool> signInWithEmailPassword(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final cleanEmail = email.trim().toLowerCase();
      if (cleanEmail.isEmpty || password.trim().isEmpty) {
        _errorMessage = 'Please enter both email and password.';
        return false;
      }

      if (!useFirebase) {
        final matched = demoUsers.firstWhere(
          (u) => u.email.toLowerCase() == cleanEmail,
          orElse: () => demoUsers.first,
        );
        _currentUser = matched;
        return true;
      }

      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );
      final user = cred.user;
      if (user == null) {
        _errorMessage = 'Authentication returned no user.';
        return false;
      }
      _currentUser = await _resolveFirebaseUser(user);
      return true;
    } on FirebaseAuthException catch (e) {
      _errorMessage = e.message ?? 'Login failed (${e.code}).';
      return false;
    } catch (e) {
      _errorMessage = 'Login failed: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// One-tap persona login for offline Demo Mode testing.
  void signInAsDemoRole(UserRole role) {
    _errorMessage = null;
    _currentUser = demoUsers.firstWhere(
      (u) => u.role == role,
      orElse: () => demoUsers.first,
    );
    notifyListeners();
  }

  void signInAsDemoUser(AppUser user) {
    _errorMessage = null;
    _currentUser = user;
    notifyListeners();
  }

  Future<AppUser> _resolveFirebaseUser(User fbUser) async {
    // 1. Prefer Firebase Auth Custom Claims (`role: MASTER | ADMIN | AGENT`)
    final tokenResult = await fbUser.getIdTokenResult(true);
    final claimRole = tokenResult.claims?['role'] as String?;

    // 2. Fallback / enrich with `users/{uid}` Firestore profile document
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(fbUser.uid)
        .get();
    final data = doc.data() ?? <String, dynamic>{};

    final role = UserRole.fromString(claimRole ?? (data['role'] as String?));
    return AppUser(
      uid: fbUser.uid,
      email: fbUser.email ?? '',
      displayName: (data['display_name'] as String?) ??
          fbUser.displayName ??
          fbUser.email ??
          'Officer',
      role: role,
      phone: data['phone'] as String? ?? '',
      branch: data['branch'] as String? ?? 'Madurai HQ',
      isActive: data['is_active'] as bool? ?? true,
    );
  }

  Future<void> signOut() async {
    if (useFirebase) {
      await FirebaseAuth.instance.signOut();
    }
    _currentUser = null;
    _errorMessage = null;
    notifyListeners();
  }
}
