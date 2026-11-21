import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/borrower_model.dart';
import '../models/loan_model.dart';
import '../models/user_model.dart';

/// Role-Based Access Control & In-App Staff Provisioning service.
class AuthService extends ChangeNotifier {
  AuthService({required this.useFirebase});

  final bool useFirebase;

  AppUser? _currentUser;
  List<AppUser> _staffDirectory = [];
  bool _isLoading = false;
  String? _errorMessage;
  bool _demoLoginEnabled = true;
  bool _isDemoSession = false;
  bool _isInitializing = true;

  bool get demoLoginEnabled => _demoLoginEnabled;
  bool get isDemoSession => _isDemoSession;
  bool get isInitializing => _isInitializing;

  AppUser? get currentUser => _currentUser;
  List<AppUser> get staffDirectory => List.unmodifiable(_staffDirectory);
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  static const List<AppUser> demoUsers = [
    AppUser(
      uid: 'uid_demo_tester',
      email: 'demo@sde-finance.in',
      displayName: 'Demo User (Tester)',
      role: UserRole.ceo,
      phone: '+919000000000',
      zone: 'All Zones',
      branch: 'Madurai HQ',
    ),
    AppUser(
      uid: 'uid_master_balaji',
      email: 'balaji@sde-finance.in',
      displayName: 'A. K. Balaji (CEO)',
      role: UserRole.ceo,
      phone: '+919842100001',
      zone: 'All Zones',
      branch: 'Madurai HQ',
    ),
    AppUser(
      uid: 'uid_md_saro',
      email: 'md@sde-finance.in',
      displayName: 'Saro Devi (MD)',
      role: UserRole.md,
      phone: '+919842100000',
      zone: 'All Zones',
      branch: 'Madurai HQ',
    ),
    AppUser(
      uid: 'uid_am_sundar',
      email: 'sundar.am@sde-finance.in',
      displayName: 'Sundaravel (Area Manager)',
      role: UserRole.areaManager,
      phone: '+919842100005',
      zone: 'Madurai',
      branch: 'Madurai Cluster',
    ),
    AppUser(
      uid: 'uid_admin_meena',
      email: 'meena@sde-finance.in',
      displayName: 'Meena Sundaram (Branch Manager)',
      role: UserRole.branchManager,
      phone: '+919842100002',
      zone: 'Madurai',
      branch: 'MADURAI',
    ),
    AppUser(
      uid: 'uid_cm_ravi',
      email: 'ravi.cm@sde-finance.in',
      displayName: 'Ravi Shankar (Collection Manager)',
      role: UserRole.collectionManager,
      phone: '+919842100006',
      zone: 'Madurai',
      branch: 'MADURAI',
    ),
    AppUser(
      uid: 'uid_agent_karthik',
      email: 'karthik@sde-finance.in',
      displayName: 'Karthik Raja (Agent)',
      role: UserRole.agent,
      phone: '+919842100011',
      zone: 'Madurai',
      branch: 'MADURAI',
    ),
    AppUser(
      uid: 'uid_agent_priya',
      email: 'priya@sde-finance.in',
      displayName: 'Priya Selvam (Agent)',
      role: UserRole.agent,
      phone: '+919842100012',
      zone: 'Madurai',
      branch: 'TIRUMANGALAM',
    ),
  ];

  List<AppUser> get allStaff {
    if (_staffDirectory.isNotEmpty) return _staffDirectory;
    return demoUsers;
  }

  List<AppUser> get activeAgents =>
      allStaff.where((u) => u.isActive && u.isAgent).toList();

  Map<String, String> get knownAgentNames => {
        for (final u in demoUsers) u.uid: u.displayName,
        for (final u in _staffDirectory) u.uid: u.displayName,
      };

  /// Filters loans strictly according to the logged-in user's role & territory.
  List<LoanModel> visibleLoansFor(
    List<LoanModel> allLoans,
    List<BorrowerModel> borrowers,
  ) {
    final user = _currentUser;
    if (user == null) return const [];
    if (user.isExecutive) return allLoans;

    if (user.isAgent) {
      return allLoans.where((l) => l.assignedAgentId == user.uid).toList();
    }

    final borrowerMap = {for (final b in borrowers) b.borrowerId: b};
    final teamUids = allStaff
        .where((s) =>
            s.uid == user.uid ||
            s.reportingManagerId == user.uid ||
            _branchMatches(user, s.branch))
        .map((s) => s.uid)
        .toSet();

    return allLoans.where((loan) {
      if (teamUids.contains(loan.assignedAgentId)) return true;
      final b = borrowerMap[loan.borrowerId];
      if (b == null) return false;
      return _branchMatches(user, b.branch ?? b.addressText);
    }).toList();
  }

  bool _branchMatches(AppUser manager, String targetBranchOrArea) {
    final target = targetBranchOrArea.trim().toLowerCase();
    if (target.isEmpty) return false;
    if (manager.isAreaManager) {
      final z = manager.zone.trim().toLowerCase();
      if (z.isNotEmpty && z != 'all zones' && target.contains(z)) return true;
    }
    final b = manager.branch.trim().toLowerCase();
    if (b.isEmpty || b == 'madurai hq' || b == 'all') return true;
    return target.contains(b);
  }

  bool _settingsListenerAttached = false;

  void _attachGlobalSettingsListener() {
    if (!useFirebase || _settingsListenerAttached) return;
    _settingsListenerAttached = true;
    FirebaseFirestore.instance
        .collection('app_config')
        .doc('settings')
        .snapshots()
        .listen((cfg) {
      if (cfg.exists && cfg.data() != null && cfg.data()!.containsKey('demo_login_enabled')) {
        final next = cfg.data()!['demo_login_enabled'] as bool? ?? true;
        if (_demoLoginEnabled != next) {
          _demoLoginEnabled = next;
          if (!next && _isDemoSession) {
            _currentUser = null;
            _isDemoSession = false;
            _errorMessage = 'Demo Sandbox has been disabled by Super Admin.';
          }
          notifyListeners();
        }
      }
    }, onError: (_) {});
  }

  Future<void> refreshGlobalSettings() async {
    if (!useFirebase) return;
    _attachGlobalSettingsListener();
    try {
      final cfg = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('settings')
          .get(const GetOptions(source: Source.serverAndCache));
      if (cfg.exists && cfg.data() != null && cfg.data()!.containsKey('demo_login_enabled')) {
        _demoLoginEnabled = cfg.data()!['demo_login_enabled'] as bool? ?? true;
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<String?> setDemoLoginEnabled(bool enabled) async {
    final previous = _demoLoginEnabled;
    _demoLoginEnabled = enabled;
    if (!enabled) {
      _staffDirectory = _staffDirectory
          .map((u) => u.uid.startsWith('uid_demo_') ? u.copyWith(isActive: false) : u)
          .toList();
    }
    notifyListeners();
    if (!useFirebase) return null;
    try {
      await FirebaseFirestore.instance
          .collection('app_config')
          .doc('settings')
          .set({
            'demo_login_enabled': enabled,
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      return null;
    } catch (e) {
      _demoLoginEnabled = previous;
      notifyListeners();
      return 'Failed to save Demo setting to Firestore: ';
    }
  }

  Future<void> init() async {
    try {
      if (!useFirebase) {
        _staffDirectory = List<AppUser>.from(demoUsers);
        return;
      }
      await refreshGlobalSettings();
      final fbUser = FirebaseAuth.instance.currentUser;
      if (fbUser != null) {
        final resolved = await _resolveFirebaseUser(fbUser);
        if (!resolved.isActive) {
          await signOut();
          return;
        }
        _isDemoSession = false;
        _currentUser = resolved;
        await refreshStaffDirectory();
      }
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> refreshStaffDirectory() async {
    if (!useFirebase) {
      if (_staffDirectory.isEmpty) {
        _staffDirectory = List<AppUser>.from(demoUsers);
      }
      notifyListeners();
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance.collection('users').get();
      final fetched = snap.docs
          .map((d) => AppUser.fromMap(d.data(), id: d.id))
          .toList();
      final merged = <String, AppUser>{
        for (final d in demoUsers) d.uid: d,
        for (final u in fetched) u.uid: u,
      };
      _staffDirectory = merged.values.toList()
        ..sort((a, b) => b.role.rank.compareTo(a.role.rank));
      notifyListeners();
    } catch (_) {
      // Retain cached directory if offline or quota-limited.
    }
  }

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
        final pool = _staffDirectory.isNotEmpty ? _staffDirectory : demoUsers;
        final matched = pool.firstWhere(
          (u) => u.email.toLowerCase() == cleanEmail,
          orElse: () => pool.first,
        );
        if (!matched.isActive) {
          _errorMessage = 'This account has been deactivated by management.';
          return false;
        }
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
      final resolved = await _resolveFirebaseUser(user);
      if (!resolved.isActive) {
        await FirebaseAuth.instance.signOut();
        _errorMessage =
            'Account suspended. Contact your Branch Manager or MD/CEO.';
        return false;
      }
      _isDemoSession = false;
      _currentUser = resolved;
      await refreshStaffDirectory();
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

  /// Creates a new staff user in-app using a secondary FirebaseApp instance
  /// so the currently signed-in MD/CEO/AM/BM/CM never loses their session.
  Future<AppUser> provisionStaffUser({
    required String displayName,
    required String email,
    required String password,
    required UserRole role,
    required String phone,
    required String zone,
    required String branch,
    List<AppFeature>? allowedFeatures,
  }) async {
    final creator = _currentUser;
    if (creator == null || !creator.creatableRoles.contains(role)) {
      throw StateError('You do not have permission to create ${role.label}.');
    }

    final cleanEmail = email.trim().toLowerCase();
    if (!useFirebase) {
      final created = AppUser(
        uid: 'uid_${role.wireValue.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch % 100000}',
        email: cleanEmail,
        displayName: displayName.trim(),
        role: role,
        phone: phone.trim(),
        zone: zone.trim(),
        branch: branch.trim().toUpperCase(),
        reportingManagerId: creator.uid,
        isActive: true,
        allowedFeatures: allowedFeatures ?? AppFeature.defaultsForRole(role),
      );
      _staffDirectory = [...allStaff, created];
      notifyListeners();
      return created;
    }

    final secondaryName = 'provision_${DateTime.now().millisecondsSinceEpoch}';
    FirebaseApp? secondaryApp;
    try {
      secondaryApp = await Firebase.initializeApp(
        name: secondaryName,
        options: Firebase.app().options,
      );
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      final cred = await secondaryAuth.createUserWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );
      final newUid = cred.user!.uid;
      await cred.user!.updateDisplayName(displayName.trim());

      final appUser = AppUser(
        uid: newUid,
        email: cleanEmail,
        displayName: displayName.trim(),
        role: role,
        phone: phone.trim(),
        zone: zone.trim(),
        branch: branch.trim().toUpperCase(),
        reportingManagerId: creator.uid,
        isActive: true,
        allowedFeatures: allowedFeatures ?? AppFeature.defaultsForRole(role),
      );

      await FirebaseFirestore.instance
          .collection('users')
          .doc(newUid)
          .set(appUser.toMap());

      await secondaryAuth.signOut();
      await refreshStaffDirectory();
      return appUser;
    } finally {
      if (secondaryApp != null) {
        await secondaryApp.delete();
      }
    }
  }

  /// Toggles active status (remote kill-switch) or updates role/branch of a staff member.
  Future<void> updateStaffUser(AppUser updated) async {
    if (!useFirebase) {
      _staffDirectory = allStaff
          .map((u) => u.uid == updated.uid ? updated : u)
          .toList();
      notifyListeners();
      return;
    }
    final baseList = _staffDirectory.isNotEmpty ? _staffDirectory : demoUsers;
    _staffDirectory = baseList
        .map((u) => u.uid == updated.uid ? updated : u)
        .toList();
    if (_currentUser?.uid == updated.uid) {
      _currentUser = updated;
    }
    notifyListeners();
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(updated.uid)
          .set(updated.toMap(), SetOptions(merge: true));
    } catch (_) {
      // Keep local state responsive even if Firestore rules/network reject
    }
  }

  void signInAsDemoRole(UserRole role) {
    _errorMessage = null;
    _currentUser = allStaff.firstWhere(
      (u) => u.role == role,
      orElse: () => demoUsers.first,
    );
    notifyListeners();
  }

  Future<String> sendPasswordReset(String email) async {
    final clean = email.trim();
    if (clean.isEmpty) {
      return 'Enter the officer email first to receive a reset link.';
    }
    if (!useFirebase) {
      return 'Demo / Sandbox mode uses 1-tap check-in; in live mode Firebase sends a reset email to $clean.';
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: clean);
      return 'Password reset link sent to $clean. Check inbox & spam.';
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Could not send password reset email.';
    }
  }

  Future<String> changeCurrentPassword(String newPassword) async {
    if (newPassword.trim().length < 6) {
      return 'New password must be at least 6 characters.';
    }
    if (!useFirebase) {
      return 'Sandbox session active — password change applies to live Firebase accounts.';
    }
    final fbUser = FirebaseAuth.instance.currentUser;
    if (fbUser == null) {
      return 'Sign in with email & temporary password first to change password.';
    }
    try {
      await fbUser.updatePassword(newPassword.trim());
      return 'Password updated successfully.';
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        return 'Please sign out and sign in once with your temporary password, then change password.';
      }
      return e.message ?? 'Could not update password.';
    }
  }

  Future<void> switchToDemoSandbox() async {
    if (useFirebase) {
      await refreshGlobalSettings();
    }
    if (!_demoLoginEnabled) {
      _errorMessage = 'Demo Sandbox has been disabled by Super Admin.';
      notifyListeners();
      return;
    }
    _isDemoSession = true;
    _currentUser = demoUsers.firstWhere(
      (u) => u.email == 'demo@sde-finance.in',
      orElse: () => demoUsers.first,
    );
    _errorMessage = null;
    notifyListeners();
  }

  void signInAsDemoUser(AppUser user) {
    if (!_demoLoginEnabled) {
      _errorMessage = 'Demo Sandbox has been disabled by Super Admin.';
      notifyListeners();
      return;
    }
    _isDemoSession = true;
    _errorMessage = null;
    _currentUser = user;
    notifyListeners();
  }

  Future<AppUser> _resolveFirebaseUser(User fbUser) async {
    final tokenResult = await fbUser.getIdTokenResult(true);
    final claimRole = tokenResult.claims?['role'] as String?;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(fbUser.uid)
        .get();
    final data = doc.data() ?? <String, dynamic>{};

    final emailLower = (fbUser.email ?? '').trim().toLowerCase();
    final isSaroDeviAdmin = emailLower.contains('saradevi');
    final role = (claimRole == null && data['role'] == null && isSaroDeviAdmin)
        ? UserRole.ceo
        : UserRole.fromString(claimRole ?? (data['role'] as String?));
    final resolved = AppUser(
      uid: fbUser.uid,
      email: fbUser.email ?? '',
      displayName: (data['display_name'] as String?) ??
          fbUser.displayName ??
          fbUser.email ??
          'Officer',
      role: role,
      phone: data['phone'] as String? ?? '',
      zone: data['zone'] as String? ?? 'Tamil Nadu South',
      branch: data['branch'] as String? ?? 'Madurai HQ',
      reportingManagerId: data['reporting_manager_id'] as String? ?? '',
      isActive: data['is_active'] as bool? ?? true,
    );

    if (!doc.exists && isSaroDeviAdmin) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(fbUser.uid)
          .set(resolved.toMap(), SetOptions(merge: true));
    }
    return resolved;
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












