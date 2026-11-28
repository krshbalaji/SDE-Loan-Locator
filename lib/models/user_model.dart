enum UserRole {
  superAdmin('SUPER_ADMIN', 'Super Admin'),
  ceo('CEO', 'CEO'),
  md('MD', 'Managing Director'),
  areaManager('AREA_MANAGER', 'Area Manager'),
  branchManager('BRANCH_MANAGER', 'Branch Manager'),
  collectionManager('COLLECTION_MANAGER', 'Collection Manager'),
  agent('AGENT', 'Collection Agent');

  const UserRole(this.wireValue, this.label);
  final String wireValue;
  final String label;

  int get rank {
    switch (this) {
      case UserRole.superAdmin:
        return 7;
      case UserRole.ceo:
        return 6;
      case UserRole.md:
        return 5;
      case UserRole.areaManager:
        return 4;
      case UserRole.branchManager:
        return 3;
      case UserRole.collectionManager:
        return 2;
      case UserRole.agent:
        return 1;
    }
  }

  static UserRole fromString(String? value) {
    final normalized = (value ?? '').trim().toUpperCase();
    switch (normalized) {
      case 'SUPER_ADMIN':
      case 'SUPERADMIN':
        return UserRole.superAdmin;
      case 'CEO':
      case 'MASTER':
        return UserRole.ceo;
      case 'MD':
        return UserRole.md;
      case 'AREA_MANAGER':
      case 'AM':
        return UserRole.areaManager;
      case 'BRANCH_MANAGER':
      case 'BM':
      case 'ADMIN':
        return UserRole.branchManager;
      case 'COLLECTION_MANAGER':
      case 'CM':
        return UserRole.collectionManager;
      case 'AGENT':
      case 'COLLECTION_AGENT':
      default:
        return UserRole.agent;
    }
  }
}

/// Granular functional modules that Super Admin can allot per user or role default.
enum AppFeature {
  overviewDashboard('OVERVIEW_DASHBOARD', 'Portfolio Overview & KPIs'),
  loansView('LOANS_VIEW', 'View Loan Accounts & Schedules'),
  loanOrigination('LOAN_ORIGINATION', 'Create / Originate New Loans'),
  loanRestructure('LOAN_RESTRUCTURE', 'What-If Simulator & Loan Restructure'),
  fieldMapRadar('FIELD_MAP_RADAR', 'Field Locator Map & Nearby Radar'),
  collectionsQueue('COLLECTIONS_QUEUE', 'Collections Queue & PTP Logging'),
  paymentCollection('PAYMENT_COLLECTION', 'Record EMI / Field Payments'),
  paymentReversal('PAYMENT_REVERSAL', 'Reverse Ledger Transactions'),
  excelImportExport('EXCEL_IMPORT_EXPORT', 'Excel / CSV Import & Vault Backup'),
  teamAndPermissions('TEAM_AND_PERMISSIONS', 'Staff Provisioning, Territory & Permissions'),
  testerActivityReport('TESTER_ACTIVITY_REPORT', 'Tester & User Activity Report');

  const AppFeature(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static AppFeature? fromString(String? value) {
    final normalized = (value ?? '').trim().toUpperCase();
    for (final f in AppFeature.values) {
      if (f.wireValue == normalized) return f;
    }
    return null;
  }

  static List<AppFeature> defaultsForRole(UserRole role) {
    switch (role) {
      case UserRole.superAdmin:
        return List<AppFeature>.from(AppFeature.values);
      case UserRole.ceo:
      case UserRole.md:
        return List<AppFeature>.from(AppFeature.values);
      case UserRole.areaManager:
        return const [
          AppFeature.overviewDashboard,
          AppFeature.loansView,
          AppFeature.loanOrigination,
          AppFeature.loanRestructure,
          AppFeature.fieldMapRadar,
          AppFeature.collectionsQueue,
          AppFeature.paymentCollection,
          AppFeature.excelImportExport,
          AppFeature.teamAndPermissions,
        ];
      case UserRole.branchManager:
        return const [
          AppFeature.overviewDashboard,
          AppFeature.loansView,
          AppFeature.loanOrigination,
          AppFeature.fieldMapRadar,
          AppFeature.collectionsQueue,
          AppFeature.paymentCollection,
          AppFeature.excelImportExport,
          AppFeature.teamAndPermissions,
        ];
      case UserRole.collectionManager:
        return const [
          AppFeature.overviewDashboard,
          AppFeature.loansView,
          AppFeature.fieldMapRadar,
          AppFeature.collectionsQueue,
          AppFeature.paymentCollection,
          AppFeature.teamAndPermissions,
        ];
      case UserRole.agent:
        return const [
          AppFeature.loansView,
          AppFeature.fieldMapRadar,
          AppFeature.collectionsQueue,
          AppFeature.paymentCollection,
        ];
    }
  }
}

class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    this.phone = '',
    this.zone = 'Tamil Nadu South',
    this.branch = 'Madurai HQ',
    this.reportingManagerId = '',
    this.isActive = true,
    this.allowedFeatures,
  });

  final String uid;
  final String email;
  final String displayName;
  final UserRole role;
  final String phone;
  final String zone;
  final String branch;
  final String reportingManagerId;
  final bool isActive;
  final List<AppFeature>? allowedFeatures;

  List<AppFeature> get effectiveFeatures =>
      allowedFeatures ?? AppFeature.defaultsForRole(role);

  bool hasFeature(AppFeature feature) {
    if (role == UserRole.superAdmin) return true;
    return effectiveFeatures.contains(feature);
  }

  bool get isSuperAdmin => role == UserRole.superAdmin;
  bool get isExecutive =>
      role == UserRole.superAdmin || role == UserRole.ceo || role == UserRole.md;
  bool get isMaster => isExecutive;
  bool get isAreaManager => role == UserRole.areaManager;
  bool get isBranchLevel =>
      role == UserRole.branchManager || role == UserRole.collectionManager;
  bool get isAdminOrAbove => role != UserRole.agent;
  bool get isAgent => role == UserRole.agent;

  /// Roles this user is authorized to provision in-app.
  List<UserRole> get creatableRoles {
    if (isSuperAdmin) return UserRole.values;
    if (role == UserRole.ceo || role == UserRole.md) {
      return UserRole.values.where((r) => r != UserRole.superAdmin).toList();
    }
    if (isAreaManager) {
      return const [
        UserRole.branchManager,
        UserRole.collectionManager,
        UserRole.agent,
      ];
    }
    if (isBranchLevel) {
      return const [UserRole.agent];
    }
    return const [];
  }

  AppUser copyWith({
    String? uid,
    String? email,
    String? displayName,
    UserRole? role,
    String? phone,
    String? zone,
    String? branch,
    String? reportingManagerId,
    bool? isActive,
    List<AppFeature>? allowedFeatures,
  }) {
    return AppUser(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      phone: phone ?? this.phone,
      zone: zone ?? this.zone,
      branch: branch ?? this.branch,
      reportingManagerId: reportingManagerId ?? this.reportingManagerId,
      isActive: isActive ?? this.isActive,
      allowedFeatures: allowedFeatures ?? this.allowedFeatures,
    );
  }

  factory AppUser.fromMap(Map<String, dynamic> map, {String? id}) {
    final role = UserRole.fromString(map['role'] as String?);
    List<AppFeature>? parsedFeatures;
    final rawFeatures = map['allowed_features'];
    if (rawFeatures is List) {
      parsedFeatures = rawFeatures
          .map((e) => AppFeature.fromString(e?.toString()))
          .whereType<AppFeature>()
          .toList();
    }
    return AppUser(
      uid: id ?? (map['uid'] as String? ?? ''),
      email: map['email'] as String? ?? '',
      displayName:
          map['display_name'] as String? ?? map['email'] as String? ?? '',
      role: role,
      phone: map['phone'] as String? ?? '',
      zone: map['zone'] as String? ?? 'Tamil Nadu South',
      branch: map['branch'] as String? ?? 'Madurai HQ',
      reportingManagerId: map['reporting_manager_id'] as String? ?? '',
      isActive: map['is_active'] as bool? ?? true,
      allowedFeatures: parsedFeatures,
    );
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'email': email,
        'display_name': displayName,
        'role': role.wireValue,
        'phone': phone,
        'zone': zone,
        'branch': branch,
        'reporting_manager_id': reportingManagerId,
        'is_active': isActive,
        'allowed_features': effectiveFeatures.map((f) => f.wireValue).toList(),
      };
}
