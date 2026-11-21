import 'dart:typed_data';
import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../engines/amortization_engine.dart';
import '../../models/borrower_model.dart';
import '../../models/collection_log_model.dart';
import '../../models/installment_model.dart';
import '../../models/loan_model.dart';
import '../../models/transaction_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_loan_service.dart';
import '../../services/location_service.dart';
import '../../services/pdf_export_service.dart';
import '../../utils/indian_formatters.dart';
import '../../widgets/ptp_log_bottom_sheet.dart';
import 'what_if_simulator_screen.dart';

/// Individual Loan 360° File: KYC, Geo-Pin, Principal vs. Interest Breakdown,
/// Tenure Progress, Appraisal Strip, CSV/PDF Export, Versioned Schedule,
/// Immutable Transactions Ledger (with Master Reversal), and Collection / PTP Logs.
class LoanDetailScreen extends StatefulWidget {
  const LoanDetailScreen({super.key, required this.loanId});

  final String loanId;

  @override
  State<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

class _LoanDetailScreenState extends State<LoanDetailScreen> {
  int? _selectedScheduleVersion;

  Future<void> _exportLoanCsv({
    required BorrowerModel? borrower,
    required LoanModel loan,
    required List<InstallmentModel> schedule,
  }) async {
    final buf = StringBuffer();
    buf.writeln('LOAN_ID,APPLICATION_NO,BORROWER_NAME,MOBILE_NO,PAN_NO,CERSAI_ID,CREDIT_SCORE,LTV_PCT,FOIR_PCT,SANCTION_AMOUNT,NET_DISBURSED,ROI_ANNUAL,TENURE,EMI_AMOUNT,PRINCIPAL_OUTSTANDING,INTEREST_OUTSTANDING,FEES_OUTSTANDING,DPD,AGING_BUCKET,STATUS');
    buf.writeln([
      loan.loanId,
      loan.applicationNo,
      '"${(borrower?.fullName ?? '').replaceAll('"', '""')}"',
      borrower?.mobilePrimary ?? '',
      borrower?.panNumber ?? '',
      borrower?.cersaiId ?? '',
      borrower?.creditScore?.toString() ?? '',
      loan.ltvPct?.toStringAsFixed(1) ?? '',
      loan.foirPct?.toStringAsFixed(1) ?? '',
      loan.principalSanctioned.toStringAsFixed(2),
      loan.netDisbursedAmount.toStringAsFixed(2),
      loan.interestRateAnnual.toStringAsFixed(2),
      loan.tenureInstallments,
      loan.emiAmount.toStringAsFixed(2),
      loan.principalOutstanding.toStringAsFixed(2),
      loan.interestOutstanding.toStringAsFixed(2),
      loan.feesOutstanding.toStringAsFixed(2),
      loan.dpd,
      loan.agingBucket.label,
      loan.status.label,
    ].join(','));

    buf.writeln('');
    buf.writeln('INSTALLMENT_NO,DUE_DATE,OPENING_PRINCIPAL,PRINCIPAL_DUE,INTEREST_DUE,TOTAL_DUE,PRINCIPAL_PAID,INTEREST_PAID,STATUS');
    for (final row in schedule) {
      buf.writeln([
        row.installmentNo,
        IndianFormatters.formatDate(row.dueDate),
        row.openingPrincipal.toStringAsFixed(2),
        row.principalDue.toStringAsFixed(2),
        row.interestDue.toStringAsFixed(2),
        row.totalDue.toStringAsFixed(2),
        row.principalPaid.toStringAsFixed(2),
        row.interestPaid.toStringAsFixed(2),
        row.status.label,
      ].join(','));
    }

    final csvBytes = Uint8List.fromList(utf8.encode(buf.toString()));
    await Printing.sharePdf(
      bytes: csvBytes,
      filename: 'Loan_Report_${loan.loanId}.csv',
    );
  }

  Future<void> _recordPaymentDialog(
    LoanPortfolioProvider portfolio,
    LoanModel loan,
    String uid,
  ) async {
    final amountCtrl =
        TextEditingController(text: loan.emiAmount.toStringAsFixed(0));
    final refCtrl = TextEditingController();
    var mode = PaymentMode.upi;
    var txnType = TransactionType.repayment;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Record Payment (Immutable Ledger)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Waterfall: Fees/Penalties → Accrued Interest → Overdue Principal → Current Principal',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<TransactionType>(
                  value: txnType,
                  decoration: const InputDecoration(
                    labelText: 'Transaction Type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: TransactionType.repayment,
                      child: Text('EMI / Regular Repayment'),
                    ),
                    DropdownMenuItem(
                      value: TransactionType.prepayment,
                      child: Text('Part / Full Prepayment'),
                    ),
                    DropdownMenuItem(
                      value: TransactionType.recovery,
                      child: Text('Delinquency Recovery'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setStateDialog(() => txnType = v);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Amount (INR)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<PaymentMode>(
                  value: mode,
                  decoration: const InputDecoration(
                    labelText: 'Payment Mode',
                    border: OutlineInputBorder(),
                  ),
                  items: PaymentMode.values
                      .where((m) => m != PaymentMode.systemAuto)
                      .map((m) =>
                          DropdownMenuItem(value: m, child: Text(m.label)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setStateDialog(() => mode = v);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: refCtrl,
                  decoration: const InputDecoration(
                    labelText: 'UTR / UPI Ref / Cheque / Receipt No',
                    border: OutlineInputBorder(),
                  ),
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
                final amount = double.tryParse(amountCtrl.text) ?? 0.0;
                if (amount <= 0) return;
                final gps = await LocationService.getCurrentLocation();
                await portfolio.recordPayment(
                  loanId: loan.loanId,
                  amount: amount,
                  paymentMode: mode,
                  referenceNo: refCtrl.text,
                  collectedByUid: uid,
                  txnType: txnType,
                  geoLat: gps.latitude,
                  geoLng: gps.longitude,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Posted ${IndianFormatters.formatInr(amount)} to ledger.',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Post Entry'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmReversal(
    LoanPortfolioProvider portfolio,
    TransactionModel txn,
    String uid,
  ) async {
    final reasonCtrl = TextEditingController(text: 'Cheque bounce / entry error');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Authorize Reversal Contra-Entry'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Original ledger entry ${txn.txnId} (${IndianFormatters.formatInr(txn.totalAmount)}) will NEVER be deleted.\n'
              'A permanent REVERSAL contra-entry will be appended.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Audit Reason',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Post Reversal'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await portfolio.reverseTransaction(
      originalTxn: txn,
      authorizedByUid: uid,
      reason: reasonCtrl.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reversal contra-entry appended to ledger.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final portfolio = context.watch<LoanPortfolioProvider>();
    final auth = context.watch<AuthService>();
    final loan = portfolio.loanById(widget.loanId);

    if (loan == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Loan Not Found')),
        body: const Center(child: Text('Loan record could not be loaded.')),
      );
    }

    final borrower = portfolio.borrowerById(loan.borrowerId);
    final product = portfolio.productById(loan.productId);
    final allSchedule = portfolio.scheduleForLoan(loan.loanId);
    final versions = allSchedule.map((e) => e.scheduleVersion).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    final viewingVersion = _selectedScheduleVersion ?? loan.scheduleVersion;
    final visibleSchedule = allSchedule
        .where((e) => e.scheduleVersion == viewingVersion)
        .toList()
      ..sort((a, b) => a.installmentNo.compareTo(b.installmentNo));
    final txns = portfolio.transactionsForLoan(loan.loanId);
    final logs = portfolio.logsForLoan(loan.loanId);

    final reversedIds = txns
        .where((t) => t.reversedTxnId != null)
        .map((t) => t.reversedTxnId!)
        .toSet();

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${loan.loanId} • ${borrower?.fullName ?? ""}'),
          actions: [
            IconButton(
              tooltip: 'Export Loan Report CSV',
              icon: const Icon(Icons.table_view_outlined),
              onPressed: () => _exportLoanCsv(
                borrower: borrower,
                loan: loan,
                schedule: visibleSchedule,
              ),
            ),
            if (borrower != null)
              IconButton(
                tooltip: 'What-If Prepayment Simulator',
                icon: const Icon(Icons.calculate_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WhatIfSimulatorScreen(
                      loan: loan,
                      borrower: borrower,
                    ),
                  ),
                ),
              ),
            if (borrower != null && product != null)
              IconButton(
                tooltip: 'Export KFS PDF',
                icon: const Icon(Icons.picture_as_pdf_outlined),
                onPressed: () async {
                  final bytes = await PdfExportService.buildKeyFactStatementPdf(
                    borrower: borrower,
                    loan: loan,
                    product: product,
                    schedule: allSchedule,
                  );
                  await PdfExportService.shareOrPrintPdf(
                    bytes,
                    'KFS_${loan.loanId}.pdf',
                  );
                },
              ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: '360° Overview'),
              Tab(text: 'Schedule'),
              Tab(text: 'Immutable Ledger'),
              Tab(text: 'CRM / PTP Logs'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // TAB 1: Overview
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (loan.earlyWarningFlag)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber, color: Colors.red.shade700),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'EARLY WARNING FLAG ACTIVE: Missed 1st EMI, consecutive partial payments, or broken PTP detected.',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                _buildBalanceAndPieCard(loan, visibleSchedule),
                const SizedBox(height: 10),
                _buildUnderwritingStrip(borrower, loan),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _recordPaymentDialog(
                        portfolio,
                        loan,
                        auth.currentUser?.uid ?? loan.assignedAgentId,
                      ),
                      icon: const Icon(Icons.currency_rupee, size: 18),
                      label: const Text('Record Payment'),
                    ),
                    if (borrower != null)
                      FilledButton.tonalIcon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => WhatIfSimulatorScreen(
                              loan: loan,
                              borrower: borrower,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.calculate, size: 18),
                        label: const Text('What-If Simulator'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => _exportLoanCsv(
                        borrower: borrower,
                        loan: loan,
                        schedule: visibleSchedule,
                      ),
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('Export CSV'),
                    ),
                    if (borrower != null)
                      OutlinedButton.icon(
                        onPressed: () async {
                          final quote = AmortizationEngine.calculatePayoffQuote(
                            loan: loan,
                            activeSchedule: visibleSchedule,
                            asOfDate: DateTime.now(),
                          );
                          final bytes =
                              await PdfExportService.buildPayoffQuotePdf(
                            borrower: borrower,
                            loan: loan,
                            quote: quote,
                          );
                          await PdfExportService.shareOrPrintPdf(
                            bytes,
                            'Payoff_${loan.loanId}.pdf',
                          );
                        },
                        icon: const Icon(Icons.description_outlined, size: 18),
                        label: const Text('Payoff Quote PDF'),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                if (borrower != null) _buildKycGeoCard(borrower),
                const SizedBox(height: 12),
                _buildLoanTermsCard(loan, product?.productName ?? loan.productId),
              ],
            ),

            // TAB 2: Versioned Schedule
            Column(
              children: [
                if (versions.length > 1)
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (final v in versions)
                          ChoiceChip(
                            label: Text(
                              v == loan.scheduleVersion
                                  ? 'Version v$v (Active)'
                                  : 'Version v$v (History)',
                            ),
                            selected: viewingVersion == v,
                            onSelected: (_) =>
                                setState(() => _selectedScheduleVersion = v),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: visibleSchedule.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, idx) {
                      final row = visibleSchedule[idx];
                      return _installmentTile(row);
                    },
                  ),
                ),
              ],
            ),

            // TAB 3: Immutable Ledger
            ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: txns.length,
              itemBuilder: (_, idx) {
                final txn = txns[idx];
                final isReversed = reversedIds.contains(txn.txnId);
                final canReverse = auth.currentUser?.isMaster == true &&
                    txn.isCreditToLoan &&
                    !isReversed;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: txn.txnType == TransactionType.reversal
                          ? Colors.red.shade100
                          : txn.isCreditToLoan
                              ? Colors.green.shade100
                              : Colors.indigo.shade100,
                      child: Icon(
                        txn.txnType == TransactionType.reversal
                            ? Icons.undo
                            : txn.isCreditToLoan
                                ? Icons.south_west
                                : Icons.north_east,
                        color: txn.txnType == TransactionType.reversal
                            ? Colors.red.shade800
                            : txn.isCreditToLoan
                                ? Colors.green.shade800
                                : Colors.indigo.shade800,
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${txn.txnType.label} • ${IndianFormatters.formatInr(txn.totalAmount)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              decoration: isReversed
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${txn.paymentMode.label} • Ref: ${txn.referenceNo} • ${IndianFormatters.formatDateTime(txn.createdAt)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          'Fees: ${IndianFormatters.formatInr(txn.allocatedFees, showDecimals: false)} | '
                          'Int: ${IndianFormatters.formatInr(txn.allocatedInterest, showDecimals: false)} | '
                          'Prin: ${IndianFormatters.formatInr(txn.allocatedPrincipal, showDecimals: false)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                        if (txn.reversedTxnId != null)
                          Text(
                            'Contra-entry reversing ${txn.reversedTxnId}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (borrower != null && txn.isCreditToLoan)
                          IconButton(
                            tooltip: 'Receipt PDF',
                            icon: const Icon(Icons.receipt_long, size: 20),
                            onPressed: () async {
                              final bytes =
                                  await PdfExportService.buildPaymentReceiptPdf(
                                borrower: borrower,
                                loan: loan,
                                txn: txn,
                              );
                              await PdfExportService.shareOrPrintPdf(
                                bytes,
                                'Receipt_${txn.referenceNo}.pdf',
                              );
                            },
                          ),
                        if (canReverse)
                          IconButton(
                            tooltip: 'Reverse (Master Only)',
                            icon: Icon(Icons.undo,
                                size: 20, color: Colors.red.shade700),
                            onPressed: () => _confirmReversal(
                              portfolio,
                              txn,
                              auth.currentUser!.uid,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),

            // TAB 4: CRM / PTP Logs
            Column(
              children: [
                if (borrower != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => PtpLogBottomSheet.show(
                          context,
                          loan: loan,
                          borrower: borrower,
                          agentId: auth.currentUser?.uid ?? loan.assignedAgentId,
                          onSave: portfolio.logCollectionActivity,
                        ),
                        icon: const Icon(Icons.add_comment),
                        label: const Text('Log Field Visit / Call / PTP'),
                      ),
                    ),
                  ),
                Expanded(
                  child: logs.isEmpty
                      ? const Center(child: Text('No collection logs recorded yet.'))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: logs.length,
                          itemBuilder: (_, idx) => _logTile(logs[idx]),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceAndPieCard(
    LoanModel loan,
    List<InstallmentModel> schedule,
  ) {
    final principalPaid = (loan.principalSanctioned - loan.principalOutstanding)
        .clamp(0.0, loan.principalSanctioned);
    final totalScheduledInterest = schedule.fold<double>(
      0.0,
      (sum, row) => sum + row.interestDue,
    );
    final paidInstallments =
        schedule.where((r) => r.status == InstallmentStatus.paid).length;
    final totalInstallments =
        loan.tenureInstallments > 0 ? loan.tenureInstallments : 1;
    final tenureProgress =
        (paidInstallments / totalInstallments).clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 112,
                  height: 112,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 24,
                      sections: [
                        PieChartSectionData(
                          value: principalPaid > 0 ? principalPaid : 1,
                          color: Colors.green.shade600,
                          title: '',
                          radius: 26,
                        ),
                        PieChartSectionData(
                          value: loan.principalOutstanding > 0
                              ? loan.principalOutstanding
                              : 0.01,
                          color: Colors.indigo.shade600,
                          title: '',
                          radius: 26,
                        ),
                        if (totalScheduledInterest > 0)
                          PieChartSectionData(
                            value: totalScheduledInterest,
                            color: Colors.amber.shade700,
                            title: '',
                            radius: 26,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Outstanding: ${IndianFormatters.formatInr(loan.totalOutstanding)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _legendRow(
                        Colors.green.shade600,
                        'Principal Paid: ${IndianFormatters.formatInr(principalPaid)}',
                      ),
                      _legendRow(
                        Colors.indigo.shade600,
                        'Principal Bal: ${IndianFormatters.formatInr(loan.principalOutstanding)}',
                      ),
                      _legendRow(
                        Colors.amber.shade700,
                        'Total Interest: ${IndianFormatters.formatInr(totalScheduledInterest)}',
                      ),
                      if (loan.feesOutstanding > 0)
                        Text(
                          'Fees/Penalties: ${IndianFormatters.formatInr(loan.feesOutstanding)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      const SizedBox(height: 6),
                      Chip(
                        label: Text(
                          '${loan.status.label} • ${loan.dpd} DPD (${loan.agingBucket.label})',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Repayment Tenure Progress',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                Text(
                  '$paidInstallments / ${loan.tenureInstallments} Installments Paid (${(tenureProgress * 100).toStringAsFixed(0)}%)',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: tenureProgress,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                color: Colors.indigo.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendRow(Color dotColor, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnderwritingStrip(BorrowerModel? borrower, LoanModel loan) {
    final badges = <String>[
      if (borrower?.creditScore != null) 'Score: ${borrower!.creditScore}',
      if (loan.ltvPct != null) 'LTV: ${loan.ltvPct!.toStringAsFixed(0)}%',
      if (loan.foirPct != null) 'FOIR: ${loan.foirPct!.toStringAsFixed(0)}%',
      if (borrower?.cersaiId != null) 'CERSAI: ${borrower!.cersaiId}',
      if (loan.assetClassification != null) 'Asset: ${loan.assetClassification}',
      if (borrower?.branch != null)
        'Branch: ${borrower!.branch}${borrower.pincode != null ? " (${borrower.pincode})" : ""}',
    ];
    if (badges.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: badges
          .map(
            (text) => Chip(
              visualDensity: VisualDensity.compact,
              backgroundColor: Colors.indigo.shade50,
              side: BorderSide(color: Colors.indigo.shade100),
              label: Text(
                text,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.indigo.shade900,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Future<void> _showUpdateGeoPinDialog(BorrowerModel borrower) async {
    final portfolio = context.read<LoanPortfolioProvider>();
    final inputCtrl = TextEditingController();
    var lat = borrower.latitude;
    var lng = borrower.longitude;
    var capturing = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text('Geo-Pin • ${borrower.fullName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current: (${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)})',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: capturing
                    ? null
                    : () async {
                        setStateDialog(() => capturing = true);
                        final res = await LocationService.getCurrentLocation();
                        setStateDialog(() {
                          capturing = false;
                          lat = res.latitude;
                          lng = res.longitude;
                        });
                      },
                icon: const Icon(Icons.my_location, size: 18),
                label: Text(
                  capturing
                      ? 'Capturing Live GPS...'
                      : 'Capture Live Device GPS Now',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  final resolved = LocationService.resolveCoordinatesForPlace(
                    addressOrCity: borrower.addressText,
                    branch: borrower.branch,
                    pincode: borrower.pincode,
                  );
                  setStateDialog(() {
                    lat = resolved.lat;
                    lng = resolved.lng;
                  });
                },
                icon: const Icon(Icons.location_city, size: 18),
                label: Text(
                  'Auto-Resolve from City/Pin (${borrower.branch ?? borrower.pincode ?? "Address"})',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: inputCtrl,
                decoration: const InputDecoration(
                  labelText: 'Or Paste Google Maps Link / Lat, Lng',
                  hintText: 'e.g. 27.8920, 77.3680 or maps.google.com/...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (val) {
                  final parsed =
                      LocationService.extractCoordinatesFromInput(val);
                  if (parsed != null) {
                    setStateDialog(() {
                      lat = parsed.lat;
                      lng = parsed.lng;
                    });
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!LocationService.isValidIndiaCoordinate(lat, lng)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Coordinates must be valid Indian latitude/longitude (6°–38°N, 68°–98°E).',
                      ),
                    ),
                  );
                  return;
                }
                await portfolio.verifyBorrowerGeoPin(
                  borrowerId: borrower.borrowerId,
                  latitude: lat,
                  longitude: lng,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Geo-Pin verified & saved: (${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)})',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Save & Mark Verified'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKycGeoCard(BorrowerModel borrower) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Borrower KYC & Geo-Location',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Chip(
                  label: Text(
                    borrower.geoVerified ? 'Geo Verified' : 'Unverified Pin',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('ID: ${borrower.borrowerId} • Mobile: ${borrower.mobilePrimary}'),
            if (borrower.coApplicantName != null)
              Text('Co-Applicant: ${borrower.coApplicantName}'),
            if (borrower.businessName != null)
              Text('Business: ${borrower.businessName}'),
            Text(
              'PAN: ${borrower.panNumber.isEmpty ? "N/A" : borrower.panNumber} | '
              'Aadhaar: ${borrower.aadhaarMasked.isEmpty ? "N/A" : borrower.aadhaarMasked}',
            ),
            if (borrower.ckycId != null || borrower.cersaiId != null)
              Text(
                'CKYC: ${borrower.ckycId ?? "N/A"} | CERSAI: ${borrower.cersaiId ?? "N/A"}',
              ),
            if (borrower.gstin != null) Text('GSTIN: ${borrower.gstin}'),
            if (borrower.bankAccountNo != null)
              Text('Bank A/C: ${borrower.bankAccountNo} (IFSC: ${borrower.bankIfsc ?? "-"})'),
            Text('Address: ${borrower.addressText}'),
            Text(
              'Coordinates: (${borrower.latitude.toStringAsFixed(5)}, ${borrower.longitude.toStringAsFixed(5)}) • Geohash: ${borrower.geohash}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => LocationService.launchGoogleMapsNavigation(
                    borrower.latitude,
                    borrower.longitude,
                  ),
                  icon: const Icon(Icons.navigation, size: 16),
                  label: const Text('Navigate'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _showUpdateGeoPinDialog(borrower),
                  icon: const Icon(Icons.add_location_alt, size: 16),
                  label: const Text('Pin / Update GPS'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      LocationService.launchPhoneCall(borrower.mobilePrimary),
                  icon: const Icon(Icons.call, size: 16),
                  label: const Text('Call'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoanTermsCard(LoanModel loan, String productName) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sanction Terms & Compliance Breakdown',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text('Product: $productName • Application: ${loan.applicationNo}'),
            Text(
              'Sanctioned: ${IndianFormatters.formatInr(loan.principalSanctioned)} | '
              'Processing Fee: ${IndianFormatters.formatInr(loan.processingFeeAmount)} + '
              '18% GST: ${IndianFormatters.formatInr(loan.gstAmount)}',
            ),
            Text(
              'Net Disbursed: ${IndianFormatters.formatInr(loan.netDisbursedAmount)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              'Rate: ${loan.interestRateAnnual}% p.a. (${loan.interestMethod.label}) • '
              '${loan.repaymentFrequency.label} x ${loan.tenureInstallments} • '
              'EMI: ${IndianFormatters.formatInr(loan.emiAmount)}',
            ),
            Text(
              'Disbursed: ${IndianFormatters.formatDate(loan.disbursementDate)} | '
              'Maturity: ${IndianFormatters.formatDate(loan.maturityDate)} | '
              'Schedule v${loan.scheduleVersion}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _installmentTile(InstallmentModel row) {
    Color badgeColor;
    switch (row.status) {
      case InstallmentStatus.paid:
        badgeColor = Colors.green.shade700;
      case InstallmentStatus.overdue:
        badgeColor = Colors.red.shade700;
      case InstallmentStatus.partial:
      case InstallmentStatus.dueToday:
        badgeColor = Colors.amber.shade800;
      case InstallmentStatus.superseded:
        badgeColor = Colors.grey.shade600;
      case InstallmentStatus.upcoming:
        badgeColor = Colors.indigo.shade600;
    }

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: badgeColor.withValues(alpha: 0.14),
          child: Text(
            '#${row.installmentNo}',
            style: TextStyle(
              color: badgeColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        title: Text(
          'Due ${IndianFormatters.formatDate(row.dueDate)} • ${IndianFormatters.formatInr(row.totalDue)}',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            decoration: row.status == InstallmentStatus.superseded
                ? TextDecoration.lineThrough
                : null,
          ),
        ),
        subtitle: Text(
          'P: ${IndianFormatters.formatInr(row.principalDue, showDecimals: false)} '
          '(Paid ${IndianFormatters.formatInr(row.principalPaid, showDecimals: false)}) | '
          'I: ${IndianFormatters.formatInr(row.interestDue, showDecimals: false)} '
          '(Paid ${IndianFormatters.formatInr(row.interestPaid, showDecimals: false)})',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: Chip(
          backgroundColor: badgeColor.withValues(alpha: 0.12),
          side: BorderSide.none,
          label: Text(
            row.status.label,
            style: TextStyle(
              color: badgeColor,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _logTile(CollectionLogModel log) {
    final ptpColor = log.ptpStatus == PtpStatus.broken
        ? Colors.red.shade700
        : log.ptpStatus == PtpStatus.kept
            ? Colors.green.shade700
            : Colors.indigo.shade700;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          log.actionType == CollectionActionType.fieldVisit
              ? Icons.location_on
              : log.actionType == CollectionActionType.whatsappReminder
                  ? Icons.chat
                  : Icons.call,
        ),
        title: Text(
          '${log.actionType.label} • ${log.disposition.label}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(log.notes),
            if (log.ptpDate != null)
              Text(
                'PTP: ${IndianFormatters.formatDate(log.ptpDate!)} for '
                '${IndianFormatters.formatInr(log.ptpAmount ?? 0, showDecimals: false)} '
                '[${log.ptpStatus.label}]',
                style: TextStyle(
                  color: ptpColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            Text(
              'Logged ${IndianFormatters.formatDateTime(log.createdAt)}'
              '${log.visitLat != null ? " • GPS (${log.visitLat!.toStringAsFixed(4)}, ${log.visitLng!.toStringAsFixed(4)})" : ""}',
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}




