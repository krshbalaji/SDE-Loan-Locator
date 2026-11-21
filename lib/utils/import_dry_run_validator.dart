import '../models/loan_model.dart';

class ImportRowIssue {
  const ImportRowIssue({
    required this.rowNumber,
    required this.loanId,
    required this.field,
    required this.message,
  });

  final int rowNumber;
  final String loanId;
  final String field;
  final String message;
}

class ImportDryRunReport {
  const ImportDryRunReport({
    required this.batchId,
    required this.totalRows,
    required this.validLoans,
    required this.issues,
  });

  final String batchId;
  final int totalRows;
  final List<LoanModel> validLoans;
  final List<ImportRowIssue> issues;

  int get invalidCount => issues.length;
  bool get hasErrors => issues.isNotEmpty;
}

/// Runs pre-commit checks on parsed loans before writing to Firestore.
class ImportDryRunValidator {
  ImportDryRunValidator._();

  static ImportDryRunReport validateLoans({
    required List<LoanModel> rows,
    Set<String> existingLoanIds = const {},
    String? batchId,
  }) {
    final resolvedBatchId = batchId ??
        'BATCH-${DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[:\-.]'), '')}';
    final seenIds = <String>{...existingLoanIds};
    final valid = <LoanModel>[];
    final issues = <ImportRowIssue>[];

    for (var i = 0; i < rows.length; i++) {
      final rowNum = i + 1;
      final loan = rows[i];
      final cleanId = loan.loanId.trim();
      var rowValid = true;

      if (cleanId.isEmpty) {
        issues.add(
          ImportRowIssue(
            rowNumber: rowNum,
            loanId: '(blank)',
            field: 'loan_id',
            message: 'Missing required loan ID.',
          ),
        );
        rowValid = false;
      } else if (seenIds.contains(cleanId.toLowerCase())) {
        issues.add(
          ImportRowIssue(
            rowNumber: rowNum,
            loanId: cleanId,
            field: 'loan_id',
            message: 'Duplicate loan ID detected in batch or existing portfolio.',
          ),
        );
        rowValid = false;
      } else {
        seenIds.add(cleanId.toLowerCase());
      }

      if (loan.principalSanctioned <= 0) {
        issues.add(
          ImportRowIssue(
            rowNumber: rowNum,
            loanId: cleanId.isEmpty ? '(blank)' : cleanId,
            field: 'principal_sanctioned',
            message: 'Sanctioned principal must be greater than 0.',
          ),
        );
        rowValid = false;
      }

      if (loan.emiAmount <= 0) {
        issues.add(
          ImportRowIssue(
            rowNumber: rowNum,
            loanId: cleanId.isEmpty ? '(blank)' : cleanId,
            field: 'emi_amount',
            message: 'EMI amount must be greater than 0.',
          ),
        );
        rowValid = false;
      }

      if (loan.principalOutstanding < 0) {
        issues.add(
          ImportRowIssue(
            rowNumber: rowNum,
            loanId: cleanId.isEmpty ? '(blank)' : cleanId,
            field: 'principal_outstanding',
            message: 'Principal outstanding cannot be negative.',
          ),
        );
        rowValid = false;
      }

      if (rowValid) {
        valid.add(loan);
      }
    }

    return ImportDryRunReport(
      batchId: resolvedBatchId,
      totalRows: rows.length,
      validLoans: valid,
      issues: issues,
    );
  }
}

