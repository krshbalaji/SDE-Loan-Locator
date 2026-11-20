import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_loan_service.dart';
import '../../utils/indian_formatters.dart';
import '../../utils/omni_search.dart';

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
    var selectedRole = allowedRoles.last;
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Create Staff Account (In-App)'),
          content: SizedBox(
            width: 420,
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
                      if (v != null) setStateDialog(() => selectedRole = v);
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
                      hintText: 'agent.name@sde-finance.in',
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
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Created ${created.role.label}: ${created.displayName} (${created.branch})',
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
    final agents = auth.activeAgents;

    if (_selectedAgentUid == null && agents.isNotEmpty) {
      _selectedAgentUid = agents.first.uid;
    }

    final scopedLoans = auth.visibleLoansFor(
      portfolio.loans,
      portfolio.borrowers,
    );
    final matchingLoans = scopedLoans.where((loan) {
      final b = portfolio.borrowerById(loan.borrowerId);
      return OmniSearchEngine.matches(
        loan: loan,
        borrower: b,
        query: _areaFilter,
      );
    }).toList();

    final discoveredAreas = portfolio.borrowers
        .map((b) => (b.branch ?? '').trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hierarchy & Staff Directory (${auth.allStaff.length})',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Signed in as ${user.role.label} • Scope: ${user.isExecutive ? "All Branches" : user.branch}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
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
                for (final staff in auth.allStaff)
                  ListTile(
                    dense: true,
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
                      '${staff.email} • Branch: ${staff.branch} • Zone: ${staff.zone}',
                    ),
                    trailing: user.role.rank > staff.role.rank
                        ? Switch(
                            value: staff.isActive,
                            onChanged: (val) => auth.updateStaffUser(
                              staff.copyWith(isActive: val),
                            ),
                          )
                        : Chip(
                            label: Text(
                              staff.isActive ? 'ACTIVE' : 'SUSPENDED',
                              style: const TextStyle(fontSize: 10),
                            ),
                            visualDensity: VisualDensity.compact,
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
                    labelText: 'Filter by Area, Pincode, Customer Name, or Loan No',
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
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _assigning ||
                              _selectedAgentUid == null ||
                              matchingLoans.isEmpty
                          ? null
                          : () async {
                              setState(() => _assigning = true);
                              final idsToAssign = _selectedLoanIds.isNotEmpty
                                  ? _selectedLoanIds.toList()
                                  : matchingLoans.map((l) => l.loanId).toList();
                              final count =
                                  await portfolio.assignAccountsToAgent(
                                loanIds: idsToAssign,
                                targetAgentUid: _selectedAgentUid!,
                              );
                              setState(() {
                                _assigning = false;
                                _selectedLoanIds.clear();
                              });
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Assigned $count accounts to ${auth.knownAgentNames[_selectedAgentUid!] ?? _selectedAgentUid}.',
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.assignment_ind, size: 18),
                      label: Text(
                        _selectedLoanIds.isNotEmpty
                            ? 'Assign Selected (${_selectedLoanIds.length})'
                            : 'Assign All (${matchingLoans.length})',
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                for (final loan in matchingLoans) ...[
                  Builder(
                    builder: (context) {
                      final b = portfolio.borrowerById(loan.borrowerId);
                      final isChecked = _selectedLoanIds.contains(loan.loanId);
                      final currentOwner =
                          auth.knownAgentNames[loan.assignedAgentId] ??
                              loan.assignedAgentId;
                      return CheckboxListTile(
                        dense: true,
                        value: isChecked,
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${b?.fullName ?? loan.borrowerId} • ${loan.loanId}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          'Area: ${b?.branch ?? "-"} ${b?.pincode ?? ""} • DPD: ${loan.dpd} • '
                          'POS: ${IndianFormatters.formatInr(loan.principalOutstanding, showDecimals: false)} • '
                          'Owner: $currentOwner',
                        ),
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedLoanIds.add(loan.loanId);
                            } else {
                              _selectedLoanIds.remove(loan.loanId);
                            }
                          });
                        },
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}


