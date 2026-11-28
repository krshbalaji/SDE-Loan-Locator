import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/activity_telemetry_service.dart';

import '../../engines/delinquency_engine.dart';
import '../../models/borrower_model.dart';
import '../../models/collection_log_model.dart';
import '../../models/loan_model.dart';
import '../../models/transaction_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_loan_service.dart';
import '../../services/location_service.dart';
import '../../utils/indian_formatters.dart';
import '../../utils/omni_search.dart';
import '../../widgets/ptp_log_bottom_sheet.dart';
import '../loans/loan_detail_screen.dart';

/// Priority-ordered Collections Queue with Omni-Search and Regular / DPD / NPA bucket filters.
class CollectionsQueueScreen extends StatefulWidget {
  const CollectionsQueueScreen({
    super.key,
    this.agentIdFilter,
    this.initialCategory,
    this.initialSearch,
  });

  final String? agentIdFilter;
  final CollectionCategory? initialCategory;
  final String? initialSearch;

  @override
  State<CollectionsQueueScreen> createState() => _CollectionsQueueScreenState();
}

class _CollectionsQueueScreenState extends State<CollectionsQueueScreen> {
  String _search = '';
  SearchFieldScope _searchScope = SearchFieldScope.all;
  CollectionCategory? _categoryFilter;
  // ignore: prefer_final_fields
  bool _zeroPaidOrStaleFilter = false;

  @override
  void initState() {
    super.initState();
    _categoryFilter = widget.initialCategory;
    if (widget.initialSearch != null && widget.initialSearch!.trim().isNotEmpty) {
      _search = widget.initialSearch!.trim();
    }
  }

  @override
  void didUpdateWidget(covariant CollectionsQueueScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCategory != widget.initialCategory) {
      setState(() => _categoryFilter = widget.initialCategory);
    }
    if (oldWidget.initialSearch != widget.initialSearch &&
        widget.initialSearch != null &&
        widget.initialSearch!.trim().isNotEmpty) {
      setState(() => _search = widget.initialSearch!.trim());
    }
  }

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
                final telemetry = context.read<ActivityTelemetryService>();
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
                telemetry.logFeatureReviewed(
                  'Recorded Queue Payment',
                  detail: 'Loan ${loan.loanId} • ${IndianFormatters.formatInr(amount)} (${mode.name})',
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
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;

    final roleScoped = widget.agentIdFilter != null
        ? portfolio.loans
            .where((l) => l.assignedAgentId == widget.agentIdFilter)
            .toList()
        : auth.visibleLoansFor(portfolio.loans, portfolio.borrowers);

    final filtered = roleScoped.where((loan) {
      if (_categoryFilter != null &&
          CollectionCategory.fromLoan(loan) != _categoryFilter) {
        return false;
      }
      if (_zeroPaidOrStaleFilter) {
        final daysSincePaid = loan.lastPaidDate == null
            ? 999
            : DateTime.now().difference(loan.lastPaidDate!).inDays;
        if (!loan.isPortfolioActive || daysSincePaid < 30) {
          return false;
        }
      }
      final b = portfolio.borrowerById(loan.borrowerId);
      return OmniSearchEngine.matches(
        loan: loan,
        borrower: b,
        query: _search,
        scope: _searchScope,
      );
    }).toList();

    final queue = DelinquencyEngine.sortCollectionsQueue(
      loans: filtered,
      allLogs: portfolio.collectionLogs,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(
            decoration: InputDecoration(
              hintText:
                  'Omni-Search: Name, Mobile, Loan No, App No, Address, Pincode...',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: _search.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _search = ''),
                    )
                  : null,
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Row(
            children: [
              FilterChip(
                label: Text('All (${roleScoped.length})'),
                selected: _categoryFilter == null,
                onSelected: (_) => setState(() => _categoryFilter = null),
              ),
              const SizedBox(width: 6),
              for (final cat in CollectionCategory.values) ...[
                FilterChip(
                  label: Text(
                    '${cat.label} (${roleScoped.where((l) => CollectionCategory.fromLoan(l) == cat).length})',
                  ),
                  selected: _categoryFilter == cat,
                  onSelected: (_) => setState(() => _categoryFilter = cat),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Row(
            children: [
              for (final scope in SearchFieldScope.values) ...[
                ChoiceChip(
                  label: Text(scope.label, style: const TextStyle(fontSize: 11)),
                  selected: _searchScope == scope,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _searchScope = scope),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        Expanded(
          child: queue.isEmpty
              ? const Center(
                  child: Text('No matching accounts in this collection bucket.'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: queue.length,
                  itemBuilder: (context, index) {
                    final loan = queue[index];
                    final borrower = portfolio.borrowerById(loan.borrowerId);
                    if (borrower == null) return const SizedBox.shrink();

                    final category = CollectionCategory.fromLoan(loan);
                    final logs = portfolio.logsForLoan(loan.loanId);
                    final hasBrokenPtp =
                        logs.any((l) => l.ptpStatus == PtpStatus.broken);
                    final openPtp = logs
                        .where((l) => l.ptpStatus == PtpStatus.open)
                        .toList();

                    final priorityColor = category == CollectionCategory.npa ||
                            loan.earlyWarningFlag ||
                            hasBrokenPtp
                        ? Colors.red.shade700
                        : category == CollectionCategory.dpd
                            ? Colors.amber.shade800
                            : Colors.green.shade700;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: priorityColor.withValues(alpha: 0.35),
                        ),
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
                                        builder: (_) => LoanDetailScreen(
                                          loanId: loan.loanId,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          borrower.fullName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                        Text(
                                          '${loan.loanId} • App: ${loan.applicationNo} • ${borrower.mobilePrimary}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.black54,
                                          ),
                                        ),
                                        Text(
                                          '${borrower.branch ?? ""} ${borrower.pincode ?? ""} • ${borrower.addressText}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11,
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
                                        category == CollectionCategory.regular
                                            ? loan.emiAmount
                                            : loan.totalOutstanding,
                                        showDecimals: false,
                                      ),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                    Text(
                                      category == CollectionCategory.npa
                                          ? 'NPA • ${loan.dpd} DPD'
                                          : category == CollectionCategory.dpd
                                              ? '${loan.dpd} DPD (SMA)'
                                              : 'EMI Due • 0 DPD',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: priorityColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            if (loan.earlyWarningFlag || openPtp.isNotEmpty || hasBrokenPtp) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                children: [
                                  if (loan.earlyWarningFlag)
                                    Chip(
                                      label: const Text(
                                        'EARLY WARNING',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.white,
                                        ),
                                      ),
                                      backgroundColor: Colors.deepOrange.shade700,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  if (hasBrokenPtp)
                                    Chip(
                                      label: const Text(
                                        'BROKEN PTP',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.white,
                                        ),
                                      ),
                                      backgroundColor: Colors.red.shade700,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  if (openPtp.isNotEmpty &&
                                      openPtp.first.ptpDate != null)
                                    Chip(
                                      label: Text(
                                        'Open PTP: ${IndianFormatters.formatDate(openPtp.first.ptpDate!)}',
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () => _showQuickPaymentDialog(
                                      context,
                                      portfolio,
                                      loan,
                                      borrower,
                                      user?.uid ?? 'uid_agent',
                                    ),
                                    icon: const Icon(Icons.payments, size: 16),
                                    label: Text(
                                      category == CollectionCategory.regular
                                          ? 'Collect EMI'
                                          : 'Collect Overdue',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => showModalBottomSheet<void>(
                                      context: context,
                                      isScrollControlled: true,
                                      builder: (sheetCtx) => PtpLogBottomSheet(
                                        loan: loan,
                                        borrower: borrower,
                                        agentId: user?.uid ?? 'uid_agent',
                                        onSave: (log) async {
                                          await portfolio.logCollectionActivity(log);
                                          if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                                        },
                                      ),
                                    ),
                                    icon: const Icon(Icons.event_note, size: 16),
                                    label: const Text('Log PTP'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}



