import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engines/conveyance_engine.dart';
import '../../engines/delinquency_engine.dart';
import '../../models/loan_model.dart';
import '../../models/loan_product_model.dart';
import '../../services/activity_telemetry_service.dart';
import '../../services/auth_service.dart';
import '../../services/app_update_service.dart';
import '../../services/firestore_loan_service.dart';
import '../../services/local_vault_service.dart';
import '../../services/location_service.dart';
import '../../services/pdf_export_service.dart';
import '../../utils/indian_formatters.dart';
import '../../widgets/aging_bucket_chart.dart';
import '../../services/portfolio_intelligence_service.dart';
import '../../widgets/conversion_deviation_intelligence_card.dart';
import '../../widgets/portfolio_intelligence_panel.dart';
import '../../widgets/governance_approvals_panel.dart';
import '../../widgets/power_bi_dimension_slice_panel.dart';
import '../../widgets/portfolio_visual_analytics_panel.dart';
import '../admin/excel_import_screen.dart';
import '../admin/tester_activity_report_screen.dart';
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
  final AppUpdateService _updateService = AppUpdateService();
  int _selectedIndex = 0;
  double _conveyanceRatePerKm = ConveyanceEngine.defaultRatePerKmInr;
  String? _selectedSliceBranch;
  String? _selectedSliceAgentId;
  String? _selectedSliceProductId;
  AnalyticsDimension? _visualDimension;
  String? _visualSliceKey;

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
          if (context.read<AuthService>().currentUser?.isSuperAdmin == true)
            IconButton(
              tooltip: 'Tester & User Activity Report',
              icon: const Icon(Icons.fact_check_outlined),
              onPressed: () {
              context
                  .read<ActivityTelemetryService>()
                  .logScreenView('Tester & User Activity Report');
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TesterActivityReportScreen(),
                ),
              );
            },
          ),
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateService.checkOnStartup();
      }
    });
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
      GovernanceApprovalsPanel(currentUser: auth.currentUser!),
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
            tooltip: 'Single-Tap APK Update',
            icon: const Icon(Icons.system_update_alt),
            onPressed: () async {
              final outcome = await _updateService.triggerGatedApkUpdate(
                allowApkDownload: auth.allowApkDownload,
                requireApkApproval: auth.requireApkApproval,
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(outcome.message)),
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
        onDestinationSelected: (i) {
            setState(() => _selectedIndex = i);
            const tabNames = [
              'Executive BI',
              'Loans',
              'Map',
              'Recovery Queue',
              'Team',
              'Import',
              'Approvals',
            ];
            final label = i < tabNames.length ? tabNames[i] : 'Tab $i';
            context.read<ActivityTelemetryService>().logScreenView(label);
          },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Executive BI',
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
            label: 'Recovery Queue',
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
    final borrowerLookup = {
      for (final b in portfolio.borrowers) b.borrowerId: b,
    };
    final visibleBaseLoans =
        auth.visibleLoansFor(portfolio.loans, portfolio.borrowers);
    final hasSliceFilter = (_selectedSliceBranch != null && _selectedSliceBranch!.isNotEmpty) ||
        (_selectedSliceAgentId != null && _selectedSliceAgentId!.isNotEmpty) ||
        (_selectedSliceProductId != null && _selectedSliceProductId!.isNotEmpty) ||
        (_visualDimension != null && _visualSliceKey != null);
    final slicedLoans = visibleBaseLoans.where((loan) {
      final b = borrowerLookup[loan.borrowerId];
      if (_selectedSliceBranch != null && _selectedSliceBranch!.isNotEmpty) {
        final br = (b?.branch ?? '').trim().isEmpty
            ? 'Unassigned Branch'
            : (b?.branch ?? '').trim();
        if (br != _selectedSliceBranch) return false;
      }
      if (_selectedSliceAgentId != null && _selectedSliceAgentId!.isNotEmpty) {
        if (loan.assignedAgentId != _selectedSliceAgentId) return false;
      }
      if (_selectedSliceProductId != null &&
          _selectedSliceProductId!.isNotEmpty) {
        if (loan.productId != _selectedSliceProductId) return false;
      }
      if (_visualDimension != null && _visualSliceKey != null) {
        final key = switch (_visualDimension!) {
          AnalyticsDimension.branch => ((b?.branch ?? '').trim().isEmpty
              ? 'Unassigned Branch'
              : (b?.branch ?? '').trim()),
          AnalyticsDimension.employee => (loan.assignedAgentId.trim().isEmpty
              ? 'Unassigned Officer'
              : loan.assignedAgentId.trim()),
          AnalyticsDimension.product => loan.productId.trim(),
          _ => '${loan.tenureInstallments}m',
        };
        if (key != _visualSliceKey) return false;
      }
      return true;
    }).toList();
    final slicedLoanIds = {for (final l in slicedLoans) l.loanId};
    final slicedTxns = portfolio.transactions
        .where((t) => slicedLoanIds.contains(t.loanId))
        .toList();
    final kpi = DelinquencyEngine.computePortfolioKpis(
      loans: slicedLoans,
      transactions: hasSliceFilter ? slicedTxns : portfolio.transactions,
      agentNames: auth.knownAgentNames,
      asOfDate: DateTime.now(),
    );

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _DashboardStoryStrip(
          kpi: kpi,
          transactions: hasSliceFilter ? slicedTxns : portfolio.transactions,
        ),
        const SizedBox(height: 12),
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
        PowerBiDimensionSlicePanel(
          loans: portfolio.loans,
          borrowers: portfolio.borrowers,
          users: auth.currentUser != null ? [auth.currentUser!] : const [],
          products: portfolio.products,
          selectedBranch: _selectedSliceBranch,
          selectedAgentId: _selectedSliceAgentId,
          selectedProductId: _selectedSliceProductId,
          onSliceChanged: ({branch, agentId, productId}) {
            setState(() {
              _selectedSliceBranch = branch;
              _selectedSliceAgentId = agentId;
              _selectedSliceProductId = productId;
            });
          },
          onResetSlices: () {
            setState(() {
              _selectedSliceBranch = null;
              _selectedSliceAgentId = null;
              _selectedSliceProductId = null;
            });
          },
        ),
        const SizedBox(height: 12),
        PortfolioVisualAnalyticsPanel(
          loans: portfolio.loans,
          borrowersById: { for (final b in portfolio.borrowers) b.borrowerId: b },
          products: portfolio.products,
          transactions: portfolio.transactions,
          selectedSliceKey: _visualSliceKey,
          onSelectSlice: (dim, key) {
            setState(() {
              _visualDimension = key == null ? null : dim;
              _visualSliceKey = key;
            });
          },
        ),
        Builder(
          builder: (context) {
            final borrowerMap = { for (final b in portfolio.borrowers) b.borrowerId: b };
            String matchVisualKey(LoanModel loan) {
              final borrower = borrowerMap[loan.borrowerId];
              switch (_visualDimension!) {
                case AnalyticsDimension.branch:
                  final rawBranch = (borrower?.branch ?? '').trim();
                  return rawBranch.isEmpty ? 'Unassigned Branch' : rawBranch;
                case AnalyticsDimension.employee:
                  final agentId = loan.assignedAgentId.trim();
                  return agentId.isEmpty ? 'Unassigned Officer' : agentId;
                case AnalyticsDimension.product:
                  final prod = loan.productId.trim();
                  return prod.isEmpty ? 'General Loan' : prod;
                case AnalyticsDimension.tenureMob:
                  final mob = loan.monthsOnBooks ?? 0;
                  if (mob <= 6) return '0-6M';
                  if (mob <= 12) return '7-12M';
                  if (mob <= 24) return '13-24M';
                  return '25M+';
                case AnalyticsDimension.creditScore:
                  final score = borrower?.creditScore;
                  if (score == null || score <= 0) return 'NTC / Unrated';
                  if (score < 650) return '< 650';
                  if (score < 700) return '650-699';
                  if (score < 750) return '700-749';
                  return '750+';
                case AnalyticsDimension.loanBand:
                  final amt = loan.principalOutstanding > 0
                      ? loan.principalOutstanding
                      : loan.principalSanctioned;
                  if (amt < 500000) return '< Rs 5L';
                  if (amt < 1500000) return 'Rs 5L-15L';
                  if (amt < 5000000) return 'Rs 15L-50L';
                  return 'Rs 50L+';
                case AnalyticsDimension.npaBand:
                  if (loan.dpd <= 0) return 'Current (0 DPD)';
                  if (loan.dpd <= 30) return '1-30 DPD';
                  if (loan.dpd <= 60) return '31-60 DPD';
                  if (loan.dpd <= 90) return '61-90 DPD';
                  return '90+ DPD (NPA)';
              }
            }
            final slicedLoans = portfolio.loans.where((loan) {
              final borrower = borrowerMap[loan.borrowerId];
              final bBranch = (borrower?.branch != null && borrower!.branch!.trim().isNotEmpty)
                  ? borrower.branch!.trim()
                  : 'Unassigned';
              if (_selectedSliceBranch != null && bBranch != _selectedSliceBranch) {
                return false;
              }
              if (_selectedSliceAgentId != null && loan.assignedAgentId != _selectedSliceAgentId) {
                return false;
              }
              if (_selectedSliceProductId != null && loan.productId != _selectedSliceProductId) {
                return false;
              }
              if (_visualDimension != null && _visualSliceKey != null && matchVisualKey(loan) != _visualSliceKey) {
                return false;
              }
              return true;
            }).toList();
            final borrowersById = {
              for (final b in portfolio.borrowers) b.borrowerId: b,
            };
            final intelligenceRecords = <LoanRecordMap>[
              for (final loan in slicedLoans)
                <String, dynamic>{
                  'loanId': loan.loanId,
                  'applicationNo': loan.applicationNo,
                  'borrowerId': loan.borrowerId,
                  'borrowerName': borrowersById[loan.borrowerId]?.fullName ?? loan.borrowerId,
                  'branch': (borrowersById[loan.borrowerId]?.branch != null &&
                          borrowersById[loan.borrowerId]!.branch!.trim().isNotEmpty)
                      ? borrowersById[loan.borrowerId]!.branch!.trim()
                      : 'Unassigned',
                  'agentId': loan.assignedAgentId,
                  'status': loan.status.name,
                  'amount': loan.principalSanctioned,
                  'principalSanctioned': loan.principalSanctioned,
                  'disbursedAmount': loan.netDisbursedAmount,
                  'pos': loan.principalOutstanding,
                  'emiAmount': loan.emiAmount,
                  'dpd': loan.dpd,
                  'isNpa': loan.dpd >= 90,
                },
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PortfolioIntelligencePanel(
                  loans: slicedLoans,
                  borrowers: portfolio.borrowers,
                ),
                const SizedBox(height: 12),
                ConversionDeviationIntelligenceCard(
                  records: intelligenceRecords,
                ),
              ],
            );
          },
        ),
            const SizedBox(height: 8),
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
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              final added = await portfolio.seedDefaultProducts();
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    added == 0
                                        ? 'All default loan products are already present.'
                                        : 'Seeded \$added default loan product(s).',
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.playlist_add_check, size: 16),
                            label: const Text('Seed Presets'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => _showProductEditorDialog(portfolio),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add Product'),
                          ),
                        ],
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
                      'Rate ${p.effectiveMinAnnualInterestRate.toStringAsFixed(1)}–${p.effectiveMaxAnnualInterestRate.toStringAsFixed(1)}% p.a. (base ${p.annualInterestRate}%) • '
                      'Tenure ${p.minTenureInstallments}–${p.maxTenureInstallments} (${p.repaymentFrequency.label}) • '
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

class _DashboardStoryStrip extends StatelessWidget {
  const _DashboardStoryStrip({
    required this.kpi,
    required this.transactions,
  });

  final dynamic kpi;
  final List<dynamic> transactions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final double par30 = (kpi.par30Percent as num?)?.toDouble() ?? 0.0;
    final double totalPos = (kpi.totalPrincipalOutstanding as num?)?.toDouble() ?? 0.0;
    final double par30Amt = (kpi.par30Amount as num?)?.toDouble() ?? 0.0;
    final double ytdCollected = (kpi.collectedYtd as num?)?.toDouble() ?? 0.0;

    final bool isHighRisk = par30 >= 10.0;
    final bool isWatch = !isHighRisk && par30 > 0.0;

    final Color statusColor = isHighRisk
        ? Colors.red.shade700
        : (isWatch ? Colors.amber.shade800 : Colors.green.shade700);
    final IconData statusIcon = isHighRisk
        ? Icons.warning_amber_rounded
        : (isWatch ? Icons.visibility_rounded : Icons.verified_rounded);
    final String statusLabel = isHighRisk
        ? 'Action Needed'
        : (isWatch ? 'Watch Zone' : 'Healthy Book');

    final double healthyRatio = totalPos <= 0
        ? 1.0
        : ((totalPos - par30Amt) / totalPos).clamp(0.0, 1.0);

    final now = DateTime.now();
    final curMonthStart = DateTime(now.year, now.month, 1);
    final nextMonthStart = DateTime(now.year, now.month + 1, 1);
    final prevMonthStart = DateTime(now.year, now.month - 1, 1);
    final qStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
    final curQStart = DateTime(now.year, qStartMonth, 1);
    final nextQStart = DateTime(now.year, qStartMonth + 3, 1);
    final prevQStart = DateTime(now.year, qStartMonth - 3, 1);
    final fyStartYear = now.month >= 4 ? now.year : now.year - 1;
    final prevFyStart = DateTime(fyStartYear - 1, 4, 1);
    final prevFySamePoint = DateTime(now.year - 1, now.month, now.day + 1);

    double sumRange(DateTime start, DateTime end) {
      var total = 0.0;
      for (final txn in transactions) {
        try {
          final dt = txn.createdAt as DateTime;
          final amt = (txn.totalAmount as num).toDouble();
          if (!dt.isBefore(start) && dt.isBefore(end)) {
            total += amt;
          }
        } catch (_) {}
      }
      return total;
    }

    String pctBadge(double cur, double prev) {
      if (prev <= 0) return 'Baseline';
      final diff = ((cur - prev) / prev) * 100.0;
      final sign = diff >= 0 ? '+' : '';
      return '$sign${diff.toStringAsFixed(0)}%';
    }

    final curM = sumRange(curMonthStart, nextMonthStart);
    final prevM = sumRange(prevMonthStart, curMonthStart);
    final curQ = sumRange(curQStart, nextQStart);
    final prevQ = sumRange(prevQStart, curQStart);
    final prevYtd = sumRange(prevFyStart, prevFySamePoint);

    final String summaryLine = totalPos <= 0
        ? 'No active principal loaded yet - import your CRIS sheet to visualize book health.'
        : '${(healthyRatio * 100).toStringAsFixed(0)}% of principal is outside PAR >30; YTD collection stands at ${IndianFormatters.formatInrCompact(ytdCollected)}.';

    Widget trendPill(String label, String value, {bool alert = false}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: alert
              ? scheme.errorContainer.withAlpha(130)
              : scheme.secondaryContainer.withAlpha(115),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$label: $value',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: alert ? scheme.onErrorContainer : scheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 18),
                const SizedBox(width: 6),
                Text(
                  statusLabel,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                Text(
                  '${(healthyRatio * 100).toStringAsFixed(0)}% Non-PAR30',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: healthyRatio,
                minHeight: 8,
                backgroundColor: Colors.red.shade100,
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              summaryLine,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface,
                  ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                trendPill('MoM', pctBadge(curM, prevM), alert: prevM > 0 && curM < prevM),
                trendPill('QoQ', pctBadge(curQ, prevQ), alert: prevQ > 0 && curQ < prevQ),
                trendPill('YoY', pctBadge(ytdCollected, prevYtd), alert: prevYtd > 0 && ytdCollected < prevYtd),
                trendPill('YTD', IndianFormatters.formatInrCompact(ytdCollected)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
