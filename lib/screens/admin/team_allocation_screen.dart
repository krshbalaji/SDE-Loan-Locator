import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/activity_telemetry_service.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_loan_service.dart';
import '../../utils/indian_formatters.dart';

class TeamAllocationScreen extends StatefulWidget {
  const TeamAllocationScreen({super.key});

  @override
  State<TeamAllocationScreen> createState() => _TeamAllocationScreenState();
}

class _TeamAllocationScreenState extends State<TeamAllocationScreen> {
  String _areaFilter = '';
  String? _selectedAgentUid;
  final Set<String> _selectedLoanIds = {};
  bool _assigning = false;

  Widget _buildFeaturePicker({
    required StateSetter setStateDialog,
    required UserRole selectedRole,
    required Set<AppFeature> selectedFeatures,
    required bool canEditFeatures,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Allotted Features & Modules',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            if (canEditFeatures)
              TextButton.icon(
                onPressed: () => setStateDialog(() {
                  selectedFeatures
                    ..clear()
                    ..addAll(AppFeature.defaultsForRole(selectedRole));
                }),
                icon: const Icon(Icons.restore, size: 15),
                label: const Text(
                  'Reset to Role Defaults',
                  style: TextStyle(fontSize: 11),
                ),
              ),
          ],
        ),
        const Text(
          'Default modules are pre-selected for each hierarchy level. Super Admin can customize per user.',
          style: TextStyle(fontSize: 11, color: Colors.black54),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final feat in AppFeature.values)
                CheckboxListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Text(
                    feat.label,
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: selectedRole == UserRole.superAdmin ||
                      selectedFeatures.contains(feat),
                  onChanged: (!canEditFeatures || selectedRole == UserRole.superAdmin)
                      ? null
                      : (checked) {
                          setStateDialog(() {
                            if (checked == true) {
                              selectedFeatures.add(feat);
                            } else {
                              selectedFeatures.remove(feat);
                            }
                          });
                        },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showEditStaffDialog(AuthService auth, AppUser staff) async {
    final nameCtrl = TextEditingController(text: staff.displayName);
    final phoneCtrl = TextEditingController(text: staff.phone);
    final zoneCtrl = TextEditingController(text: staff.zone);
    final branchCtrl = TextEditingController(text: staff.branch);
    var selectedRole = staff.role;
    var isActive = staff.isActive;
    final selectedFeatures = Set<AppFeature>.from(staff.effectiveFeatures);
    final canEditFeatures = auth.currentUser?.isSuperAdmin == true ||
        auth.currentUser?.isExecutive == true;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text('Edit Staff • ${staff.displayName}'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<UserRole>(
                    value: selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Hierarchy Role',
                      border: OutlineInputBorder(),
                    ),
                    items: UserRole.values
                        .map((r) =>
                            DropdownMenuItem(value: r, child: Text(r.label)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setStateDialog(() {
                          selectedRole = v;
                          selectedFeatures
                            ..clear()
                            ..addAll(AppFeature.defaultsForRole(v))..remove(AppFeature.testerActivityReport);
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Display Name *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Mobile (+91)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: zoneCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Zone / Cluster',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: branchCtrl,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Branch / Area *',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Account Active'),
                    value: isActive,
                    onChanged: (v) => setStateDialog(() => isActive = v),
                  ),
                  _buildFeaturePicker(
                    setStateDialog: setStateDialog,
                    selectedRole: selectedRole,
                    selectedFeatures: selectedFeatures,
                    canEditFeatures: canEditFeatures,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                await auth.updateStaffUser(
                  staff.copyWith(
                    displayName: nameCtrl.text.trim(),
                    role: selectedRole,
                    phone: phoneCtrl.text.trim(),
                    zone: zoneCtrl.text.trim(),
                    branch: branchCtrl.text.trim().toUpperCase(),
                    isActive: isActive,
                    allowedFeatures: selectedRole == UserRole.superAdmin
                        ? AppFeature.defaultsForRole(UserRole.superAdmin)
                        : selectedFeatures.toList(),
                  ),
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateStaffDialog(AuthService auth) async {
    final creator = auth.currentUser!;
    final allowedRoles = creator.creatableRoles;
    if (allowedRoles.isEmpty) return;

    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController(text: 'Sde@2026');
    final phoneCtrl = TextEditingController();
    final zoneCtrl = TextEditingController(
      text: creator.isExecutive ? 'Madurai' : creator.zone,
    );
    final branchCtrl = TextEditingController(
      text: creator.isExecutive ? 'MADURAI' : creator.branch,
    );
    var selectedRole =
        creator.isSuperAdmin ? UserRole.branchManager : allowedRoles.last;
    final selectedFeatures = Set<AppFeature>.from(AppFeature.defaultsForRole(selectedRole))..remove(AppFeature.testerActivityReport);
    final canEditFeatures = creator.isSuperAdmin || creator.isExecutive;
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text(
            creator.isSuperAdmin
                ? 'Super Admin — Create User & Allot Features'
                : 'Create Staff Account (In-App)',
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<UserRole>(
                    value: selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Hierarchy Role *',
                      border: OutlineInputBorder(),
                    ),
                    items: allowedRoles
                        .map((r) =>
                            DropdownMenuItem(value: r, child: Text(r.label)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setStateDialog(() {
                          selectedRole = v;
                          selectedFeatures
                            ..clear()
                            ..addAll(AppFeature.defaultsForRole(v))..remove(AppFeature.testerActivityReport);
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Full Name *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Login Email *',
                      hintText: 'officer.name@sde-finance.in',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: passCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Temporary Password (min 6 chars) *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Mobile (+91)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: zoneCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Zone / Cluster',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: branchCtrl,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Branch / Area *',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  _buildFeaturePicker(
                    setStateDialog: setStateDialog,
                    selectedRole: selectedRole,
                    selectedFeatures: selectedFeatures,
                    canEditFeatures: canEditFeatures,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      if (nameCtrl.text.trim().isEmpty ||
                          !emailCtrl.text.contains('@') ||
                          passCtrl.text.length < 6) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Enter valid name, email, and 6+ character password.',
                            ),
                          ),
                        );
                        return;
                      }
                      setStateDialog(() => saving = true);
                      try {
                        final created = await auth.provisionStaffUser(
                          displayName: nameCtrl.text,
                          email: emailCtrl.text,
                          password: passCtrl.text,
                          role: selectedRole,
                          phone: phoneCtrl.text,
                          zone: zoneCtrl.text,
                          branch: branchCtrl.text,
                          allowedFeatures: selectedRole == UserRole.superAdmin
                              ? AppFeature.defaultsForRole(UserRole.superAdmin)
                              : selectedFeatures.toList(),
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Created ${created.role.label}: ${created.displayName} (${created.effectiveFeatures.length} features)',
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        setStateDialog(() => saving = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed: $e')),
                          );
                        }
                      }
                    },
              icon: const Icon(Icons.person_add),
              label: Text(saving ? 'Creating...' : 'Create User'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final portfolio = context.watch<LoanPortfolioProvider>();
    final user = auth.currentUser!;
    final staffList = auth.allStaff;
    final agents = auth.activeAgents;
    final visibleLoans = auth.visibleLoansFor(
      portfolio.loans,
      portfolio.borrowers,
    );
    final borrowerMap = {
      for (final b in portfolio.borrowers) b.borrowerId: b,
    };

    final discoveredAreas = <String>{
      for (final b in portfolio.borrowers) ...[
        if ((b.branch ?? '').trim().isNotEmpty) b.branch!.trim().toUpperCase(),
        if ((b.pincode ?? '').trim().isNotEmpty) b.pincode!.trim(),
      ],
    }.toList()
      ..sort();

    final filteredLoans = visibleLoans.where((loan) {
      if (_areaFilter.trim().isEmpty) return true;
      final q = _areaFilter.trim().toLowerCase();
      final b = borrowerMap[loan.borrowerId];
      final haystack = [
        loan.loanId,
        loan.applicationNo,
        b?.fullName ?? '',
        b?.branch ?? '',
        b?.pincode ?? '',
        b?.addressText ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(q);
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (user.isExecutive)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: SwitchListTile(
              title: const Text(
                'Demo Check-In / Sandbox Access (Global)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                auth.demoLoginEnabled
                    ? 'Demo Sandbox login is ON across sessions.'
                    : 'Demo Sandbox login is OFF across sessions and new browser windows.',
              ),
              value: auth.demoLoginEnabled,
              onChanged: (val) async {
                await auth.setDemoLoginEnabled(val);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        val
                            ? 'Demo Sandbox login enabled.'
                            : 'Demo Sandbox login turned OFF.',
                      ),
                    ),
                  );
                }
              },
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hierarchy & Staff Directory (${staffList.length})',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Signed in as ${user.role.label} • ${user.effectiveFeatures.length}/${AppFeature.values.length} features active',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                    if (user.creatableRoles.isNotEmpty)
                      FilledButton.icon(
                        onPressed: () => _showCreateStaffDialog(auth),
                        icon: const Icon(Icons.person_add, size: 18),
                        label: const Text('New Staff'),
                      ),
                  ],
                ),
                const Divider(height: 20),
                for (final staff in staffList)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: staff.isActive
                          ? Colors.indigo.shade50
                          : Colors.grey.shade200,
                      child: Text(
                        staff.role.wireValue.substring(0, 2),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: staff.isActive
                              ? Colors.indigo.shade900
                              : Colors.grey,
                        ),
                      ),
                    ),
                    title: Text(
                      '${staff.displayName} • ${staff.role.label}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration:
                            staff.isActive ? null : TextDecoration.lineThrough,
                      ),
                    ),
                    subtitle: Text(
                      '${staff.email} • ${staff.branch} • ${staff.effectiveFeatures.length} features',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (user.isSuperAdmin ||
                            user.isExecutive ||
                            user.role.rank > staff.role.rank)
                          IconButton(
                            tooltip: 'Edit Staff & Features',
                            icon: const Icon(Icons.edit_outlined, size: 19),
                            onPressed: () => _showEditStaffDialog(auth, staff),
                          ),
                        if (user.isAdminOrAbove && staff.uid != user.uid)
                          Switch(
                            value: staff.isActive,
                            onChanged: (val) => auth.updateStaffUser(
                              staff.copyWith(isActive: val),
                            ),
                          )
                        else
                          Chip(
                            label: Text(
                              staff.isActive ? 'ACTIVE' : 'SUSPENDED',
                              style: const TextStyle(fontSize: 10),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Territory & Customer Allocation',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Filter by Area, Branch, Pincode, or Customer Name and assign matching accounts to a Collection Agent.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 10),
                if (discoveredAreas.isNotEmpty) ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChip(
                          label: const Text('All Areas'),
                          selected: _areaFilter.isEmpty,
                          onSelected: (_) => setState(() {
                            _areaFilter = '';
                            _selectedLoanIds.clear();
                          }),
                        ),
                        const SizedBox(width: 6),
                        for (final area in discoveredAreas) ...[
                          FilterChip(
                            label: Text(area),
                            selected:
                                _areaFilter.toUpperCase() == area.toUpperCase(),
                            onSelected: (_) => setState(() {
                              _areaFilter = area;
                              _selectedLoanIds.clear();
                            }),
                          ),
                          const SizedBox(width: 6),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  decoration: InputDecoration(
                    labelText:
                        'Filter by Area, Pincode, Customer Name, or Loan No',
                    prefixIcon: const Icon(Icons.travel_explore),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: _areaFilter.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() => _areaFilter = ''),
                          )
                        : null,
                  ),
                  onChanged: (v) => setState(() {
                    _areaFilter = v;
                    _selectedLoanIds.clear();
                  }),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: agents.any((a) => a.uid == _selectedAgentUid)
                            ? _selectedAgentUid
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Target Collection Agent',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: agents
                            .map((a) => DropdownMenuItem(
                                  value: a.uid,
                                  child: Text(
                                    '${a.displayName} (${a.branch})',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedAgentUid = v),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: (_assigning ||
                              _selectedLoanIds.isEmpty ||
                              _selectedAgentUid == null)
                          ? null
                          : () async {
                              final telemetry = context.read<ActivityTelemetryService>();
                              final assignedCount = _selectedLoanIds.length;
                              final targetAgent = _selectedAgentUid!;
                              setState(() => _assigning = true);
                              try {
                                await portfolio.assignAccountsToAgent(
                                  loanIds: _selectedLoanIds.toList(),
                                  targetAgentUid: targetAgent,
                                );
                                telemetry.logFeatureReviewed(
                                  'Allocated Loans to Staff',
                                  detail: 'Assigned $assignedCount loan(s) to agent $targetAgent',
                                );
                                _selectedLoanIds.clear();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Accounts assigned.'),
                                    ),
                                  );
                                }
                              } finally {
                                if (mounted) {
                                  setState(() => _assigning = false);
                                }
                              }
                            },
                      icon: const Icon(Icons.assignment_ind, size: 18),
                      label: Text(
                        _assigning
                            ? 'Assigning...'
                            : 'Assign (${_selectedLoanIds.length})',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final loan in filteredLoans)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _selectedLoanIds.contains(loan.loanId),
                    onChanged: (checked) {
                      setState(() {
                        if (checked == true) {
                          _selectedLoanIds.add(loan.loanId);
                        } else {
                          _selectedLoanIds.remove(loan.loanId);
                        }
                      });
                    },
                    title: Text(
                      '${borrowerMap[loan.borrowerId]?.fullName ?? loan.borrowerId} • ${loan.loanId}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '${borrowerMap[loan.borrowerId]?.branch ?? '—'} • Pos: ${IndianFormatters.formatInr(loan.principalOutstanding)} • DPD: ${loan.dpd}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}


