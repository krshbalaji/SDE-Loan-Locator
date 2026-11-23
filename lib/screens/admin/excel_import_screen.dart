import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/loan_model.dart';
import '../../models/loan_product_model.dart';
import '../../services/auth_service.dart';
import '../../services/excel_import_service.dart';
import '../../services/firestore_loan_service.dart';
import '../../utils/indian_formatters.dart';
import '../../utils/import_dry_run_validator.dart';

/// Bulk Excel (.xlsx) & NBFC Master (.csv) import screen supporting both simple sheets
/// (`Location`, `ApplicationNo`, `LoanNo`, `CustomerName`, `Amount`, `LatLong`, `MobileNo`) and full NBFC master sheets
/// (`LOAN_ID`, `APPLICANT_NAME`, `SANCTION_AMOUNT`, `ROI`, `TENURE`, `MOB`, `DPD`, `PROPERTY_LATLONG`, etc.).
class ExcelImportScreen extends StatefulWidget {
  const ExcelImportScreen({super.key});

  @override
  State<ExcelImportScreen> createState() => _ExcelImportScreenState();
}

class _ExcelImportScreenState extends State<ExcelImportScreen> {
  ExcelParseResult? _parseResult;
  LoanProductModel? _selectedProduct;
  String _selectedAgentId = 'uid_agent_karthik';
  bool _overwriteExisting = false;
  bool _committing = false;
  ExcelImportMode _importMode = ExcelImportMode.append;

  Future<void> _pickExcel(LoanPortfolioProvider portfolio) async {
    final result = await ExcelImportService.pickAndParseExcel(
      existingBorrowers: portfolio.borrowers,
      existingLoans: portfolio.loans,
    );
    if (result == null || !mounted) return;
    setState(() {
      _parseResult = result;
      _selectedProduct ??=
          portfolio.products.isNotEmpty ? portfolio.products.first : null;
    });
  }

  Future<void> _clearDemoData(LoanPortfolioProvider portfolio) async {
    final repo = portfolio.repository;
    if (repo is! InMemoryDemoLoanService) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Demo Portfolio Data?'),
        content: const Text(
          'This removes all current sample/imported borrowers, loans, schedules, and transactions in Demo Sandbox so you can import fresh data cleanly.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear Data'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    repo.clearAllData();
    await portfolio.refresh();
    if (!mounted) return;
    setState(() => _parseResult = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Demo portfolio cleared in 1 tap. Ready for fresh import.'),
      ),
    );
  }

  Future<void> _commit(
    LoanPortfolioProvider portfolio,
    AuthService auth,
  ) async {
    final parse = _parseResult;
    final product = _selectedProduct ??
        (portfolio.products.isNotEmpty ? portfolio.products.first : null);
    if (parse == null || product == null) return;

    if (_overwriteExisting) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Overwrite Existing Records?'),
          content: const Text(
            'Overwrite mode clears existing demo/portfolio entries before committing the new file. Choose Append if you want to keep existing records.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Overwrite & Import'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _committing = true);
    try {
      final count = await ExcelImportService.commitImport(
        parseResult: parse,
        portfolio: portfolio,
        defaultProduct: product,
        assignedAgentId: _selectedAgentId,
        importedByUid: auth.currentUser?.uid ?? 'uid_admin_meena',
        mode: _importMode,
      );
      if (!mounted) return;
      final skipped = parse.rows.length - count;
      final skipNote = skipped > 0 ? ' ($skipped invalid row(s) skipped)' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported $count of ${parse.rows.length} row(s) in ${_overwriteExisting ? "Overwrite" : "Append"} mode$skipNote.',
          ),
        ),
      );
      setState(() => _parseResult = null);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Import stopped: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _committing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final portfolio = context.watch<LoanPortfolioProvider>();
    final auth = context.watch<AuthService>();
    final product = _selectedProduct ??
        (portfolio.products.isNotEmpty ? portfolio.products.first : null);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Smart Excel (.xlsx) & NBFC Master (.csv) Bulk Ingestion',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Supports standard sheets (Location, ApplicationNo, LoanNo, CustomerName, Amount, LatLong, MobileNo) '
                  'AND full NBFC master headers (LOAN_ID, APPLICANT_NAME, SANCTION_AMOUNT, ROI, TENURE, MOB, DPD, PROPERTY_LATLONG, PAN_NO, CERSAI_ID).',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (product != null)
                      SizedBox(
                        width: 260,
                        child: DropdownButtonFormField<LoanProductModel>(
                          value: product,
                          decoration: const InputDecoration(
                            labelText: 'Default Loan Product',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: portfolio.products
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p,
                                  child: Text(p.productName),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _selectedProduct = v),
                        ),
                      ),
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String>(
                        value: _selectedAgentId,
                        decoration: const InputDecoration(
                          labelText: 'Assign to Agent',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: auth.knownAgentNames.entries
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value.split(' (').first),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _selectedAgentId = v);
                        },
                      ),
                    ),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment<bool>(
                          value: false,
                          icon: Icon(Icons.playlist_add),
                          label: Text('Append'),
                        ),
                        ButtonSegment<bool>(
                          value: true,
                          icon: Icon(Icons.find_replace),
                          label: Text('Overwrite'),
                        ),
                      ],
                      selected: <bool>{_overwriteExisting},
                      onSelectionChanged: (selection) {
                        if (selection.isNotEmpty) {
                          setState(() => _overwriteExisting = selection.first);
                        }
                      },
                    ),
                    FilledButton.icon(
                      onPressed: () => _pickExcel(portfolio),
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Select .xlsx / .csv File'),
                    ),
                    if (portfolio.isDemoMode)
                      OutlinedButton.icon(
                        onPressed: () => _clearDemoData(portfolio),
                        icon: const Icon(Icons.delete_sweep_outlined),
                        label: const Text('Clear Demo Data'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                SegmentedButton<ExcelImportMode>(
                  segments: const [
                    ButtonSegment<ExcelImportMode>(
                      value: ExcelImportMode.append,
                      icon: Icon(Icons.add_circle_outline),
                      label: Text('Append'),
                    ),
                    ButtonSegment<ExcelImportMode>(
                      value: ExcelImportMode.selectiveUpdate,
                      icon: Icon(Icons.edit_note),
                      label: Text('Selective Update'),
                    ),
                    ButtonSegment<ExcelImportMode>(
                      value: ExcelImportMode.overwrite,
                      icon: Icon(Icons.sync),
                      label: Text('Overwrite'),
                    ),
                  ],
                  selected: {_importMode},
                  onSelectionChanged: (selection) {
                    setState(() => _importMode = selection.first);
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  _importMode == ExcelImportMode.selectiveUpdate
                      ? 'Selective Update: Updates only existing loans matching LoanNo or ApplicationNo in the uploaded file; untouched loans stay as-is.'
                      : (_importMode == ExcelImportMode.overwrite
                          ? 'Overwrite: Imports full sheet records while preserving verified GPS pins when rows lack coordinates.'
                          : 'Append: Adds rows from the uploaded file onto the existing portfolio.'),
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
        if (_parseResult != null) ...[
          const SizedBox(height: 12),
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
                          'Preview: ${_parseResult!.fileName} '
                          '(${_parseResult!.validCount} valid / ${_parseResult!.rows.length} rows • ${ImportDryRunValidator.validateLoans(rows: _parseResult!.rows.where((r) => r.isValid).map((r) {
    final now = DateTime.now();
    final tenure = r.tenureInstallments > 0 ? r.tenureInstallments : 12;
    final roi = r.customRoi ?? 12.0;
    final emi = r.amount / tenure;
    return LoanModel(
      loanId: r.loanNo.trim(),
      applicationNo: r.applicationNo.trim().isEmpty ? r.loanNo.trim() : r.applicationNo.trim(),
      borrowerId: r.mobilePrimary.trim(),
      productId: _selectedProduct?.productId ?? 'PROD_DEFAULT',
      assignedAgentId: _selectedAgentId,
      principalSanctioned: r.amount,
      processingFeeAmount: 0,
      gstAmount: 0,
      netDisbursedAmount: r.amount,
      interestRateAnnual: roi,
      interestMethod: InterestMethod.reducingBalance,
      tenureInstallments: tenure,
      emiAmount: emi,
      disbursementDate: now,
      firstDueDate: now.add(const Duration(days: 30)),
      maturityDate: now.add(Duration(days: 30 * tenure)),
      principalOutstanding: r.principalOutstandingOverride ?? r.amount,
      dpd: r.dpd ?? 0,
      agingBucket: AgingBucket.fromDpd(r.dpd ?? 0),
    );
  }).toList()).invalidCount} dry-run issues) • '
                          'Mode: ${_overwriteExisting ? "Overwrite" : "Append"}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed:
                            _committing || _parseResult!.validCount == 0
                                ? null
                                : () => _commit(portfolio, auth),
                        icon: _committing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.cloud_upload),
                        label: Text('Import ${_parseResult!.validCount} Loans'),
                      ),
                    ],
                  ),
                  if (_parseResult!.errors.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _parseResult!.errors.join('\n'),
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  const SizedBox(height: 10),
                  for (final row in _parseResult!.rows)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        row.isValid ? Icons.check_circle : Icons.error_outline,
                        color: row.isValid
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                      title: Text(
                        'Row ${row.rowNumber}: ${row.customerName} (${row.loanNo.isEmpty ? "Auto ID" : row.loanNo}) — '
                        '${IndianFormatters.formatInr(row.amount, showDecimals: false)}',
                      ),
                      subtitle: Text(
                        '${row.mobilePrimary} • ${row.location}'
                        '${row.monthsOnBooks != null ? " • MOB ${row.monthsOnBooks}/${row.tenureInstallments}" : ""}'
                        '${row.latitude != null ? " • (${row.latitude!.toStringAsFixed(4)}, ${row.longitude!.toStringAsFixed(4)})" : ""}'
                        '${row.warnings.isNotEmpty ? "\n⚠ ${row.warnings.join('; ')}" : ""}',
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}











