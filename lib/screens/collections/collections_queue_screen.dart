import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engines/delinquency_engine.dart';
import '../../models/borrower_model.dart';
import '../../models/collection_log_model.dart';
import '../../models/loan_model.dart';
import '../../models/transaction_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_loan_service.dart';
import '../../services/location_service.dart';
import '../../utils/indian_formatters.dart';
import '../../widgets/ptp_log_bottom_sheet.dart';
import '../loans/loan_detail_screen.dart';

/// Priority-ordered Collections Queue:
/// `early_warning_flag` -> `Broken PTP` -> `DPD descending` -> `Outstanding descending`.
class CollectionsQueueScreen extends StatelessWidget {
  const CollectionsQueueScreen({
    super.key,
    this.agentIdFilter,
  });

  final String? agentIdFilter;

  Future<void> _showQuickPaymentDialog(
    BuildContext context,
    LoanPortfolioProvider portfolio,
    LoanModel loan,
    BorrowerModel borrower,
    String uid,
  ) async {
    final amountCtrl = TextEditingController(
      text: loan.emiAmount.toStringAsFixed(0),
    );
    final refCtrl = TextEditingController();
    var mode = PaymentMode.upi;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: Text('Record Payment • ${loan.loanId}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Waterfall order: Fees → Interest → Overdue Principal → Current Principal',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Amount Received (₹)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<PaymentMode>(
                value: mode,
                decoration: const InputDecoration(
                  labelText: 'Payment Rail',
                  border: OutlineInputBorder(),
                ),
                items: PaymentMode.values
                    .where((m) => m != PaymentMode.systemAuto)
                    .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setModalState(() => mode = v);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: refCtrl,
                decoration: const InputDecoration(
                  labelText: 'UTR / UPI Ref / Receipt No',
                  border: OutlineInputBorder(),
                ),
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
                final amount = double.tryParse(amountCtrl.text) ?? 0;
                if (amount <= 0) return;
                final loc = await LocationService.getCurrentLocation();
                await portfolio.recordPayment(
                  loanId: loan.loanId,
                  amount: amount,
                  paymentMode: mode,
                  referenceNo: refCtrl.text,
                  collectedByUid: uid,
                  geoLat: loc.latitude,
                  geoLng: loc.longitude,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Recorded ${IndianFormatters.formatInr(amount)} to immutable ledger.',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Post Payment'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final portfolio = context.watch<LoanPortfolioProvider>();
    final user = context.watch<AuthService>().currentUser;

    final scopedLoans = agentIdFilter == null
        ? portfolio.loans
        : portfolio.loans
            .where((l) => l.assignedAgentId == agentIdFilter)
            .toList();

    final queue = DelinquencyEngine.sortCollectionsQueue(
      loans: scopedLoans,
      allLogs: portfolio.collectionLogs,
    );

    if (queue.isEmpty) {
      return const Center(child: Text('No active accounts in collections queue.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: queue.length,
      itemBuilder: (context, index) {
        final loan = queue[index];
        final borrower = portfolio.borrowerById(loan.borrowerId);
        if (borrower == null) return const SizedBox.shrink();

        final logs = portfolio.logsForLoan(loan.loanId);
        final hasBrokenPtp = logs.any((l) => l.ptpStatus == PtpStatus.broken);
        final openPtp = logs.where((l) => l.ptpStatus == PtpStatus.open).toList();

        final priorityColor = loan.earlyWarningFlag || hasBrokenPtp || loan.dpd > 30
            ? Colors.red.shade700
            : loan.dpd > 0
                ? Colors.amber.shade800
                : Colors.green.shade700;

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: priorityColor.withValues(alpha: 0.35)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: priorityColor,
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LoanDetailScreen(loanId: loan.loanId),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              borrower.fullName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              '${loan.loanId} • ${borrower.mobilePrimary}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          IndianFormatters.formatInr(
                            loan.totalOutstanding,
                            showDecimals: false,
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '${loan.dpd} DPD • ${loan.agingBucket.label}',
                          style: TextStyle(
                            fontSize: 11,
                            color: priorityColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (loan.earlyWarningFlag)
                      _pill('EARLY WARNING', Colors.red.shade700),
                    if (hasBrokenPtp)
                      _pill('BROKEN PTP', Colors.deepOrange.shade700),
                    if (openPtp.isNotEmpty && openPtp.first.ptpDate != null)
                      _pill(
                        'OPEN PTP: ${IndianFormatters.formatDate(openPtp.first.ptpDate!)} (${IndianFormatters.formatInr(openPtp.first.ptpAmount ?? 0, showDecimals: false)})',
                        Colors.indigo.shade700,
                      ),
                  ],
                ),
                const Divider(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () =>
                          LocationService.launchPhoneCall(borrower.mobilePrimary),
                      icon: const Icon(Icons.call, size: 16),
                      label: const Text('Call'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => LocationService.launchWhatsAppReminder(
                        mobile: borrower.mobilePrimary,
                        message:
                            'Namaste ${borrower.fullName}, payment reminder from Saro Devi Enterprises '
                            'for Loan ${loan.loanId}. Current DPD: ${loan.dpd} days. '
                            'EMI: ${IndianFormatters.formatInr(loan.emiAmount, showDecimals: false)}. Please arrange via UPI/NEFT.',
                      ),
                      icon: const Icon(Icons.chat, size: 16),
                      label: const Text('WhatsApp'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => PtpLogBottomSheet.show(
                        context,
                        loan: loan,
                        borrower: borrower,
                        agentId: user?.uid ?? loan.assignedAgentId,
                        onSave: portfolio.logCollectionActivity,
                      ),
                      icon: const Icon(Icons.event_note, size: 16),
                      label: const Text('Log PTP'),
                    ),
                    FilledButton.icon(
                      onPressed: () => _showQuickPaymentDialog(
                        context,
                        portfolio,
                        loan,
                        borrower,
                        user?.uid ?? loan.assignedAgentId,
                      ),
                      icon: const Icon(Icons.currency_rupee, size: 16),
                      label: const Text('Record Payment'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
