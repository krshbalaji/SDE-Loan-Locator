enum UserRole {
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

  bool get isExecutive => role == UserRole.ceo || role == UserRole.md;
  bool get isMaster => isExecutive;
  bool get isAreaManager => role == UserRole.areaManager;
  bool get isBranchLevel =>
      role == UserRole.branchManager || role == UserRole.collectionManager;
  bool get isAdminOrAbove => role != UserRole.agent;
  bool get isAgent => role == UserRole.agent;

  /// Roles this manager is authorized to provision in-app.
  List<UserRole> get creatableRoles {
    if (isExecutive) return UserRole.values;
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
    );
  }

  factory AppUser.fromMap(Map<String, dynamic> map, {String? id}) {
    return AppUser(
      uid: id ?? (map['uid'] as String? ?? ''),
      email: map['email'] as String? ?? '',
      displayName:
          map['display_name'] as String? ?? map['email'] as String? ?? '',
      role: UserRole.fromString(map['role'] as String?),
      phone: map['phone'] as String? ?? '',
      zone: map['zone'] as String? ?? 'Tamil Nadu South',
      branch: map['branch'] as String? ?? 'Madurai HQ',
      reportingManagerId: map['reporting_manager_id'] as String? ?? '',
      isActive: map['is_active'] as bool? ?? true,
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
      };
}
