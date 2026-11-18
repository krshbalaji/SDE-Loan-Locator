enum UserRole {
  master('MASTER', 'Master'),
  admin('ADMIN', 'Admin'),
  agent('AGENT', 'Field Agent');

  const UserRole(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static UserRole fromString(String? value) {
    final normalized = (value ?? '').trim().toUpperCase();
    return UserRole.values.firstWhere(
      (r) => r.wireValue == normalized,
      orElse: () => UserRole.agent,
    );
  }
}

class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    this.phone = '',
    this.branch = 'Madurai HQ',
    this.isActive = true,
  });

  final String uid;
  final String email;
  final String displayName;
  final UserRole role;
  final String phone;
  final String branch;
  final bool isActive;

  bool get isMaster => role == UserRole.master;
  bool get isAdminOrAbove => role == UserRole.master || role == UserRole.admin;
  bool get isAgent => role == UserRole.agent;

  factory AppUser.fromMap(Map<String, dynamic> map, {String? id}) {
    return AppUser(
      uid: id ?? (map['uid'] as String? ?? ''),
      email: map['email'] as String? ?? '',
      displayName: map['display_name'] as String? ?? map['email'] as String? ?? '',
      role: UserRole.fromString(map['role'] as String?),
      phone: map['phone'] as String? ?? '',
      branch: map['branch'] as String? ?? 'Madurai HQ',
      isActive: map['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'email': email,
        'display_name': displayName,
        'role': role.wireValue,
        'phone': phone,
        'branch': branch,
        'is_active': isActive,
      };
}
