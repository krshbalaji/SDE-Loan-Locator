import 'package:flutter/material.dart';

import '../models/borrower_model.dart';
import '../models/loan_model.dart';
import '../models/loan_product_model.dart';
import '../models/user_model.dart';
import '../utils/indian_formatters.dart';

enum PowerBiSliceAxis { branch, person, product }

class PowerBiDimensionSlicePanel extends StatefulWidget {
  const PowerBiDimensionSlicePanel({
    super.key,
    required this.loans,
    required this.borrowers,
    required this.users,
    required this.products,
    this.selectedBranch,
    this.selectedAgentId,
    this.selectedProductId,
    this.onSliceChanged,
    this.onResetSlices,
  });

  final List<LoanModel> loans;
  final List<BorrowerModel> borrowers;
  final List<AppUser> users;
  final List<LoanProductModel> products;
  final String? selectedBranch;
  final String? selectedAgentId;
  final String? selectedProductId;
  final void Function({
    String? branch,
    String? agentId,
    String? productId,
  })? onSliceChanged;
  final VoidCallback? onResetSlices;

  @override
  State<PowerBiDimensionSlicePanel> createState() =>
      _PowerBiDimensionSlicePanelState();
}

class _PowerBiDimensionSlicePanelState extends State<PowerBiDimensionSlicePanel> {
  PowerBiSliceAxis _axis = PowerBiSliceAxis.branch;

  @override
  Widget build(BuildContext context) {
    final borrowerById = {
      for (final b in widget.borrowers) b.borrowerId: b,
    };
    final userById = {
      for (final u in widget.users) u.uid: u,
    };
    final productById = {
      for (final p in widget.products) p.productId: p,
    };

    final filteredLoans = widget.loans.where((loan) {
      final borrower = borrowerById[loan.borrowerId];
      final agent = userById[loan.assignedAgentId];
      final effectiveBranch =
          (borrower?.branch != null && borrower!.branch!.trim().isNotEmpty)
              ? borrower.branch!.trim()
              : ((agent != null && agent.branch.trim().isNotEmpty)
                  ? agent.branch.trim()
                  : 'Unassigned');

      if (widget.selectedBranch != null &&
          effectiveBranch != widget.selectedBranch) {
        return false;
      }
      if (widget.selectedAgentId != null &&
          loan.assignedAgentId != widget.selectedAgentId) {
        return false;
      }
      if (widget.selectedProductId != null &&
          loan.productId != widget.selectedProductId) {
        return false;
      }
      return true;
    }).toList();

    final grouped = <String, _SliceAccumulator>{};
    for (final loan in filteredLoans) {
      final borrower = borrowerById[loan.borrowerId];
      final agent = userById[loan.assignedAgentId];
      final product = productById[loan.productId];

      String key;
      String label;
      String? sliceBranch;
      String? sliceAgentId;
      String? sliceProductId;

      switch (_axis) {
        case PowerBiSliceAxis.branch:
          final bName =
              (borrower?.branch != null && borrower!.branch!.trim().isNotEmpty)
                  ? borrower.branch!.trim()
                  : ((agent != null && agent.branch.trim().isNotEmpty)
                      ? agent.branch.trim()
                      : 'Unassigned');
          key = bName;
          label = bName;
          sliceBranch = bName;
        case PowerBiSliceAxis.person:
          final pKey = loan.assignedAgentId.trim().isEmpty
              ? 'unassigned'
              : loan.assignedAgentId.trim();
          key = pKey;
          label = (agent != null && agent.displayName.trim().isNotEmpty)
              ? agent.displayName.trim()
              : pKey;
          sliceAgentId = pKey;
        case PowerBiSliceAxis.product:
          final prKey = loan.productId.trim().isEmpty
              ? 'unassigned'
              : loan.productId.trim();
          key = prKey;
          label = (product != null && product.productName.trim().isNotEmpty)
              ? product.productName.trim()
              : prKey;
          sliceProductId = prKey;
      }

      final acc = grouped.putIfAbsent(
        key,
        () => _SliceAccumulator(
          key: key,
          label: label,
          branchFilter: sliceBranch,
          agentFilter: sliceAgentId,
          productFilter: sliceProductId,
        ),
      );
      acc.loanCount += 1;
      acc.totalPos += loan.principalOutstanding;
      final elapsedMonths = (loan.netDisbursedAmount > 0 && loan.emiAmount > 0)
          ? (((loan.netDisbursedAmount - loan.principalOutstanding).clamp(0.0, loan.netDisbursedAmount)) / loan.emiAmount)
              .round()
              .clamp(0, loan.tenureInstallments)
          : 0;
      final collectedEst = elapsedMonths * loan.emiAmount;
      final overdueEst = loan.dpd > 0 ? ((loan.dpd / 30.0).ceil() * loan.emiAmount) : 0.0;
      final demandEst = collectedEst + overdueEst + (loan.status == LoanStatus.closed ? 0.0 : loan.emiAmount);
      acc.totalDemand += demandEst;
      acc.totalCollected += collectedEst;
      acc.totalDpd += loan.dpd;
      if (loan.dpd >= 90 || loan.agingBucket == AgingBucket.dpd90Plus) {
        acc.npaPos += loan.principalOutstanding;
        acc.npaLoans += 1;
      }
    }

    final rows = grouped.values.toList()
      ..sort((a, b) => b.npaPosPct.compareTo(a.npaPosPct));

    final hasActiveSlice = widget.selectedBranch != null ||
        widget.selectedAgentId != null ||
        widget.selectedProductId != null;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 8,
              spacing: 12,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Executive BI Slice Matrix',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Slice across Branch, Person, and Product • Tap a row to cross-filter',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SegmentedButton<PowerBiSliceAxis>(
                      segments: const [
                        ButtonSegment(
                          value: PowerBiSliceAxis.branch,
                          label: Text('Branch'),
                          icon: Icon(Icons.apartment, size: 16),
                        ),
                        ButtonSegment(
                          value: PowerBiSliceAxis.person,
                          label: Text('Person'),
                          icon: Icon(Icons.person_outline, size: 16),
                        ),
                        ButtonSegment(
                          value: PowerBiSliceAxis.product,
                          label: Text('Product'),
                          icon: Icon(Icons.category_outlined, size: 16),
                        ),
                      ],
                      selected: {_axis},
                      onSelectionChanged: (next) {
                        if (next.isNotEmpty) {
                          setState(() => _axis = next.first);
                        }
                      },
                    ),
                    if (hasActiveSlice && widget.onResetSlices != null) ...[
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: widget.onResetSlices,
                        icon: const Icon(Icons.filter_alt_off, size: 16),
                        label: const Text('Reset'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            if (hasActiveSlice) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (widget.selectedBranch != null)
                    Chip(label: Text('Branch: ${widget.selectedBranch}')),
                  if (widget.selectedAgentId != null)
                    Chip(label: Text('Person: ${widget.selectedAgentId}')),
                  if (widget.selectedProductId != null)
                    Chip(label: Text('Product: ${widget.selectedProductId}')),
                ],
              ),
            ],
            const SizedBox(height: 12),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No loans match the active filter selection.'),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Segment')),
                    DataColumn(label: Text('Loans'), numeric: true),
                    DataColumn(label: Text('Total POS'), numeric: true),
                    DataColumn(label: Text('Demand'), numeric: true),
                    DataColumn(label: Text('Collected'), numeric: true),
                    DataColumn(label: Text('Coll %'), numeric: true),
                    DataColumn(label: Text('NPA POS'), numeric: true),
                    DataColumn(label: Text('NPA POS %'), numeric: true),
                    DataColumn(label: Text('Avg DPD'), numeric: true),
                  ],
                  rows: [
                    for (final r in rows)
                      DataRow(
                        onSelectChanged: widget.onSliceChanged == null
                            ? null
                            : (_) => widget.onSliceChanged!(
                                  branch: r.branchFilter,
                                  agentId: r.agentFilter,
                                  productId: r.productFilter,
                                ),
                        cells: [
                          DataCell(
                            Text(
                              r.label,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          DataCell(Text('${r.loanCount}')),
                          DataCell(Text(IndianFormatters.formatInr(r.totalPos))),
                          DataCell(Text(IndianFormatters.formatInr(r.totalDemand))),
                          DataCell(Text(IndianFormatters.formatInr(r.totalCollected))),
                          DataCell(
                            Text(
                              '${r.collectionPct.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: r.collectionPct >= 85.0
                                    ? Colors.green.shade700
                                    : Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                          DataCell(Text(IndianFormatters.formatInr(r.npaPos))),
                          DataCell(
                            Text(
                              '${r.npaPosPct.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: r.npaPosPct >= 5.0
                                    ? Theme.of(context).colorScheme.error
                                    : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          DataCell(Text(r.avgDpd.toStringAsFixed(0))),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SliceAccumulator {
  _SliceAccumulator({
    required this.key,
    required this.label,
    this.branchFilter,
    this.agentFilter,
    this.productFilter,
  });

  final String key;
  final String label;
  final String? branchFilter;
  final String? agentFilter;
  final String? productFilter;
  int loanCount = 0;
  int npaLoans = 0;
  double totalPos = 0;
  double totalDemand = 0;
  double totalCollected = 0;
  double npaPos = 0;
  int totalDpd = 0;

  double get collectionPct => totalDemand <= 0 ? 0 : (totalCollected / totalDemand) * 100.0;
  double get npaPosPct => totalPos <= 0 ? 0 : (npaPos / totalPos) * 100.0;
  double get avgDpd => loanCount == 0 ? 0 : totalDpd / loanCount;
}
