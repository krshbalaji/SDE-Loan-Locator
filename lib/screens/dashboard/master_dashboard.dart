import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engines/conveyance_engine.dart';
import '../../engines/delinquency_engine.dart';
import '../../models/loan_product_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_loan_service.dart';
import '../../services/local_vault_service.dart';
import '../../services/location_service.dart';
import '../../services/pdf_export_service.dart';
import '../../utils/indian_formatters.dart';
import '../../widgets/aging_bucket_chart.dart';
import '../admin/excel_import_screen.dart';
import '../admin/team_allocation_screen.dart';
import '../collections/collections_queue_screen.dart';
import '../loans/loan_list_screen.dart';
import '../map/field_locator_map_screen.dart';

/// Master & Admin Command Center with Portfolio KPIs, PAR > 30 %, Aging Chart,
/// Agent Collection Efficiency Leaderboard, and full Product Template CRUD.
class MasterDashboard extends StatefulWidget {
  const MasterDashboard({super.key});

  @override
  State<MasterDashboard> createState() => _MasterDashboardState();
}

class _MasterDashboardState extends State<MasterDashboard> {
  int _selectedIndex = 0;
  double _conveyanceRatePerKm = ConveyanceEngine.defaultRatePerKmInr;

  Future<void> _showProductEditorDialog(
    LoanPortfolioProvider portfolio, {
    LoanProductModel? existing,
  }) async {
    final nameCtrl = TextEditingController(text: existing?.productName ?? '');
    final rateCtrl = TextEditingController(
      text: (existing?.annualInterestRate ?? 20.0).toString(),
    );
    final tenureCtrl = TextEditingController(
      text: (existing?.maxTenureInstallments ?? 24).toString(),
    );
    final feeCtrl = TextEditingController(
      text: (existing?.processingFeePct ?? 2.0).toString(),
    );
    final gstCtrl = TextEditingController(
      text: (existing?.gstRatePct ?? 18.0).toString(),
    );
    final graceCtrl = TextEditingController(
      text: (existing?.gracePeriodDays ?? 3).toString(),
    );
    final lateValCtrl = TextEditingController(
      text: (existing?.lateFeeValue ?? 2.0).toString(),
    );
    final riskDpdCtrl = TextEditingController(
      text: (existing?.atRiskDpdThreshold ?? 30).toString(),
    );
    var method = existing?.interestMethod ?? InterestMethod.reducingBalance;
    var freq = existing?.repaymentFrequency ?? RepaymentFrequency.monthly;
    var lateType = existing?.lateFeeType ?? LateFeeType.percentOverdue;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text(
            existing == null
                ? 'Create Loan Product Template'
                : 'Edit Product: ${existing.productName}',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Product Name *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<InterestMethod>(
                  value: method,
                  decoration: const InputDecoration(
                    labelText: 'Interest Method',
                    border: OutlineInputBorder(),
                  ),
                  items: InterestMethod.values
                      .map((m) =>
                          DropdownMenuItem(value: m, child: Text(m.label)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setStateDialog(() => method = v);
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<RepaymentFrequency>(
                  value: freq,
                  decoration: const InputDecoration(
                    labelText: 'Repayment Frequency',
                    border: OutlineInputBorder(),
                  ),
                  items: RepaymentFrequency.values
                      .map((f) =>
                          DropdownMenuItem(value: f, child: Text(f.label)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setStateDialog(() => freq = v);
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: rateCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Annual Rate (%)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: tenureCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Max Tenure',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: feeCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Proc. Fee (%)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: gstCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'GST Rate (%)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: graceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Grace Days',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: riskDpdCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'At-Risk DPD',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<LateFeeType>(
                        value: lateType,
                        decoration: const InputDecoration(
                          labelText: 'Late Fee Type',
                          border: OutlineInputBorder(),
                        ),
                        items: LateFeeType.values
                            .map((t) => DropdownMenuItem(
                                  value: t,
                                  child: Text(t.label, overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setStateDialog(() => lateType = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: lateValCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: lateType == LateFeeType.flatInr
                              ? 'Fee (INR)'
                              : 'Fee (%)',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
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
                final product = LoanProductModel(
                  productId: existing?.productId ??
                      'PROD-${DateTime.now().millisecondsSinceEpoch % 10000}',
                  productName: nameCtrl.text.trim(),
                  interestMethod: method,
                  annualInterestRate: double.tryParse(rateCtrl.text) ?? 20.0,
                  repaymentFrequency: freq,
                  maxTenureInstallments: int.tryParse(tenureCtrl.text) ?? 24,
                  processingFeePct: double.tryParse(feeCtrl.text) ?? 2.0,
                  gstRatePct: double.tryParse(gstCtrl.text) ?? 18.0,
                  gracePeriodDays: int.tryParse(graceCtrl.text) ?? 3,
                  lateFeeType: lateType,
                  lateFeeValue: double.tryParse(lateValCtrl.text) ?? 2.0,
                  atRiskDpdThreshold: int.tryParse(riskDpdCtrl.text) ?? 30,
                  isActive: existing?.isActive ?? true,
                );
                await portfolio.saveProduct(product);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(existing == null ? 'Save Template' : 'Update Template'),
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

    final titles = [
      'Portfolio Command (${user.role.label})',
      'Loans Portfolio',
      'Field Geo-Locator',
      'Collections Queue',
      'Team & Territory',
      'Excel Bulk Import',
    ];

    final pages = [
      _buildOverview(context, portfolio, auth),
      const LoanListScreen(),
      const FieldLocatorMapScreen(),
      const CollectionsQueueScreen(),
      const TeamAllocationScreen(),
      const ExcelImportScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_selectedIndex]),
        actions: [
          if (portfolio.isDemoMode)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Chip(
                label: Text('DEMO', style: TextStyle(fontSize: 10)),
                visualDensity: VisualDensity.compact,
              ),
            ),
          IconButton(
            tooltip: 'Import Excel / CSV',
            icon: const Icon(Icons.upload_file),
            onPressed: () => setState(() => _selectedIndex = 5),
          ),
          IconButton(
            tooltip: 'Download Latest Android APK',
            icon: const Icon(Icons.android),
            onPressed: () => LocationService.launchExternalUrl('https://github.com/krshbalaji/SDE-Loan-Locator/releases/latest'),
          ),
          IconButton(
            tooltip: 'Backup Local Drive Vault (.json)',
            icon: const Icon(Icons.save_alt),
            onPressed: () async {
              await LocalVaultService.exportVaultToLocalDrive(portfolio);
            },
          ),
          IconButton(
            tooltip: 'Restore Local Drive Vault (.json)',
            icon: const Icon(Icons.restore_page_outlined),
            onPressed: () async {
              final n = await LocalVaultService.restoreVaultFromLocalDrive(portfolio);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Restored $n accounts from Local Vault.')),
              );
            },
          ),
          IconButton(
            tooltip: 'Run Daily DPD & PTP Sweep',
            icon: const Icon(Icons.sync),
            onPressed: () async {
              final n = await portfolio.runDailyDelinquencySweep();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Daily DPD & aging sweep updated $n active loans.')),
              );
            },
          ),
          IconButton(
            tooltip: 'Sign Out',
            icon: const Icon(Icons.logout),
            onPressed: () => auth.signOut(),
          ),
        ],
      ),
      body: portfolio.isLoading && portfolio.loans.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Loans',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_late_outlined),
            selectedIcon: Icon(Icons.assignment_late),
            label: 'Queue',
          ),
          NavigationDestination(
            icon: Icon(Icons.upload_file_outlined),
            selectedIcon: Icon(Icons.upload_file),
            label: 'Import',
          ),
        ],
      ),
    );
  }

  Widget _buildOverview(
    BuildContext context,
    LoanPortfolioProvider portfolio,
    AuthService auth,
  ) {
    final now = DateTime.now();
    final conveyanceList = ConveyanceEngine.computePeriodConveyance(
      logs: portfolio.collectionLogs,
      transactions: portfolio.transactions,
      borrowers: portfolio.borrowers,
      agentNames: auth.knownAgentNames,
      fromDate: DateTime(now.year, now.month, 1),
      toDate: now,
      ratePerKmInr: _conveyanceRatePerKm,
    );
    final kpi = DelinquencyEngine.computePortfolioKpis(
      loans: auth.visibleLoansFor(portfolio.loans, portfolio.borrowers),
      transactions: portfolio.transactions,
      agentNames: auth.knownAgentNames,
      asOfDate: DateTime.now(),
    );

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _kpiTile(
              'Deployed Capital',
              IndianFormatters.formatInrCompact(kpi.totalDeployedCapital),
              '${kpi.activeLoansCount} Active Loans',
              Colors.indigo,
            ),
            _kpiTile(
              'Principal Outstanding',
              IndianFormatters.formatInrCompact(kpi.totalPrincipalOutstanding),
              'Int: ${IndianFormatters.formatInrCompact(kpi.totalInterestOutstanding)}',
              Colors.blueGrey,
            ),
            _kpiTile(
              'Collected (MTD / YTD)',
              IndianFormatters.formatInrCompact(kpi.collectedMtd),
              'YTD: ${IndianFormatters.formatInrCompact(kpi.collectedYtd)}',
              Colors.green.shade700,
            ),
            _kpiTile(
              'PAR > 30 Days',
              '${kpi.par30Percent.toStringAsFixed(1)}%',
              '${IndianFormatters.formatInrCompact(kpi.par30Amount)} • ${kpi.earlyWarningCount} EWS',
              kpi.par30Percent > 10 ? Colors.red.shade700 : Colors.amber.shade800,
            ),
          ],
        ),
        const SizedBox(height: 14),
        AgingBucketChart(breakdown: kpi.agingBreakdown),
        const SizedBox(height: 14),
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
                      child: Text(
                        'Agent Collection Efficiency Leaderboard',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final delinquent = portfolio.loans
                            .where((l) => l.dpd > 0)
                            .toList()
                          ..sort((a, b) => b.dpd.compareTo(a.dpd));
                        final bytes =
                            await PdfExportService.buildArrearsReportPdf(
                          delinquentLoans: delinquent,
                          borrowerMap: {
                            for (final b in portfolio.borrowers) b.borrowerId: b,
                          },
                        );
                        await PdfExportService.shareOrPrintPdf(
                          bytes,
                          'SDE_Arrears_Report.pdf',
                        );
                      },
                      icon: const Icon(Icons.picture_as_pdf, size: 16),
                      label: const Text('Arrears PDF'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final agent in kpi.agentLeaderboard)
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      child: Text(agent.agentName.substring(0, 1)),
                    ),
                    title: Text(agent.agentName),
                    subtitle: Text(
                      '${agent.assignedLoans} loans • MTD ${IndianFormatters.formatInr(agent.collectedAmount, showDecimals: false)} • PAR30: ${agent.par30Count}',
                    ),
                    trailing: Text(
                      '${agent.efficiencyPct.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: agent.efficiencyPct >= 75
                            ? Colors.green.shade700
                            : Colors.orange.shade800,
                      ),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'Field Travel & Local Conveyance (MTD)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.two_wheeler, size: 16),
                      label: Text('₹/km'),
                      onPressed: () {
                        setState(() {
                          _conveyanceRatePerKm = _conveyanceRatePerKm >= 8.0
                              ? 3.5
                              : _conveyanceRatePerKm + 1.0;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                for (final c in conveyanceList)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: Colors.teal.shade50,
                      child: Icon(Icons.route, color: Colors.teal.shade800, size: 18),
                    ),
                    title: Text(
                      c.agentName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      ' km across d • '
                      ' verified visits • '
                      'Yield /km',
                    ),
                    trailing: Text(
                      IndianFormatters.formatInr(c.reimbursementInr, showDecimals: false),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.teal.shade800,
                      ),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Loan Product Templates (${portfolio.products.length})',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (auth.currentUser?.isMaster == true)
                      FilledButton.tonalIcon(
                        onPressed: () => _showProductEditorDialog(portfolio),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Product'),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                for (final p in portfolio.products)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      p.productName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${p.annualInterestRate}% p.a. (${p.interestMethod.label}) • '
                      '${p.repaymentFrequency.label} (max ${p.maxTenureInstallments}) • '
                      'Fee ${p.processingFeePct}% + ${p.gstRatePct}% GST • '
                      'Grace ${p.gracePeriodDays}d • Late ${p.lateFeeType == LateFeeType.flatInr ? "₹${p.lateFeeValue.toStringAsFixed(0)}" : "${p.lateFeeValue}%"} • '
                      'Risk ${p.atRiskDpdThreshold}d',
                    ),
                    trailing: auth.currentUser?.isMaster == true
                        ? IconButton(
                            tooltip: 'Edit Product Template',
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: () => _showProductEditorDialog(
                              portfolio,
                              existing: p,
                            ),
                          )
                        : null,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _kpiTile(String title, String value, String sub, Color accent) {
    return SizedBox(
      width: 175,
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: accent.withValues(alpha: 0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: accent,
                ),
              ),
              const SizedBox(height: 2),
              Text(sub, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}




