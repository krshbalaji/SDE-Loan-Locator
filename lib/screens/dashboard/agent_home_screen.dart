import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/activity_telemetry_service.dart';

import '../../engines/conveyance_engine.dart';
import '../../engines/delinquency_engine.dart';
import '../../models/collection_log_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_loan_service.dart';
import '../../utils/indian_formatters.dart';
import '../../utils/omni_search.dart';
import '../collections/collections_queue_screen.dart';
import '../loans/loan_list_screen.dart';
import '../map/field_locator_map_screen.dart';

/// Field Agent workspace strictly scoped to `assigned_agent_id == currentUser.uid`,
/// featuring real-time GPS travel distance & automated Local Conveyance (TA/DA) calculation.
class AgentHomeScreen extends StatefulWidget {
  const AgentHomeScreen({super.key});

  @override
  State<AgentHomeScreen> createState() => _AgentHomeScreenState();
}

class _AgentHomeScreenState extends State<AgentHomeScreen> {
  CollectionCategory? _selectedCategory;
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final portfolio = context.watch<LoanPortfolioProvider>();
    final user = auth.currentUser!;

    final myLoans = portfolio.loans
        .where((l) => l.assignedAgentId == user.uid)
        .toList();
    final myLogs = portfolio.collectionLogs
        .where((l) => l.agentId == user.uid)
        .toList();
    final myTxns = portfolio.transactions
        .where((t) => t.collectedByUid == user.uid)
        .toList();

    final now = DateTime.now();
    final kpi = DelinquencyEngine.computePortfolioKpis(
      loans: myLoans,
      transactions: myTxns,
      agentNames: {user.uid: user.displayName},
      asOfDate: now,
    );

    final mtdConveyanceList = ConveyanceEngine.computePeriodConveyance(
      logs: myLogs,
      transactions: myTxns,
      borrowers: portfolio.borrowers,
      agentNames: {user.uid: user.displayName},
      fromDate: DateTime(now.year, now.month, 1),
      toDate: now,
    );
    final mtdConv =
        mtdConveyanceList.isNotEmpty ? mtdConveyanceList.first : null;

    final todayConveyanceList = ConveyanceEngine.computePeriodConveyance(
      logs: myLogs,
      transactions: myTxns,
      borrowers: portfolio.borrowers,
      agentNames: {user.uid: user.displayName},
      fromDate: DateTime(now.year, now.month, now.day),
      toDate: now,
    );
    final todayConv =
        todayConveyanceList.isNotEmpty ? todayConveyanceList.first : null;

    final openPtps =
        myLogs.where((l) => l.ptpStatus == PtpStatus.open).toList();
    final brokenPtps =
        myLogs.where((l) => l.ptpStatus == PtpStatus.broken).toList();

    final pages = [
      ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome, ${user.displayName}',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text('Branch: ${user.branch} • Assigned Accounts: ${myLoans.length}'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      Text(
                        'MTD Collected: ${IndianFormatters.formatInr(kpi.collectedMtd, showDecimals: false)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text('Open PTPs: ${openPtps.length}'),
                      Text(
                        'Broken PTPs: ${brokenPtps.length}',
                        style: TextStyle(
                          color: brokenPtps.isNotEmpty
                              ? Colors.red.shade800
                              : null,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.two_wheeler, color: Colors.teal.shade700),
                      const SizedBox(width: 8),
                      const Text(
                        'Auto Field Travel & Local Conveyance',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      Text(
                        'Today: ${(todayConv?.verifiedRoadKm ?? 0).toStringAsFixed(1)} km (${IndianFormatters.formatInr(todayConv?.reimbursementInr ?? 0, showDecimals: false)})',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'MTD: ${(mtdConv?.verifiedRoadKm ?? 0).toStringAsFixed(1)} km • Claim: ${IndianFormatters.formatInr(mtdConv?.reimbursementInr ?? 0, showDecimals: false)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.teal.shade800,
                        ),
                      ),
                      Text(
                        'Verified Stops: ${mtdConv?.verifiedOnSiteStops ?? 0} • Yield: ${IndianFormatters.formatInr(mtdConv?.collectionPerKmInr ?? 0, showDecimals: false)}/km',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    context.read<ActivityTelemetryService>().logFeatureReviewed('Started Field Route');
                    setState(() => _selectedIndex = 1);
                  },
                  icon: const Icon(Icons.route),
                  label: const Text('Start Field Route'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    context.read<ActivityTelemetryService>().logFeatureReviewed('Opened Collections Queue');
                    setState(() => _selectedIndex = 2);
                  },
                  icon: const Icon(Icons.assignment_late),
                  label: const Text('Collections Queue'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Active Open / Broken PTP Follow-ups',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (openPtps.isEmpty && brokenPtps.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No pending PTP follow-ups right now.'),
              ),
            ),
          for (final log in [...brokenPtps, ...openPtps])
            Card(
              child: ListTile(
                leading: Icon(
                  log.ptpStatus == PtpStatus.broken
                      ? Icons.warning
                      : Icons.event_available,
                  color: log.ptpStatus == PtpStatus.broken
                      ? Colors.red.shade700
                      : Colors.amber.shade800,
                ),
                title: Text(
                  '${portfolio.borrowerById(log.borrowerId)?.fullName ?? log.borrowerId} • ${log.loanId}',
                ),
                subtitle: Text(
                  '${log.ptpStatus.label} • ${log.ptpDate != null ? IndianFormatters.formatDate(log.ptpDate!) : "-"} • '
                  '${IndianFormatters.formatInr(log.ptpAmount ?? 0, showDecimals: false)}\n${log.notes}',
                ),
              ),
            ),
        ],
      ),
      FieldLocatorMapScreen(lockedAgentId: user.uid),
      CollectionsQueueScreen(agentIdFilter: user.uid, initialCategory: _selectedCategory),
      LoanListScreen(agentIdFilter: user.uid),
    ];

    // PortfolioIntelligencePanel available for agent beat/portfolio view
    return Scaffold(
      appBar: AppBar(
        title: Text('Field Officer • ${user.displayName.split(" (").first}'),
        actions: [
          IconButton(
            tooltip: 'Sign Out',
            icon: const Icon(Icons.logout),
            onPressed: () => auth.signOut(),
          ),
        ],
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Field Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_late_outlined),
            selectedIcon: Icon(Icons.assignment_late),
            label: 'Queue',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_shared_outlined),
            selectedIcon: Icon(Icons.folder_shared),
            label: 'My Loans',
          ),
        ],
      ),
    );
  }
}



