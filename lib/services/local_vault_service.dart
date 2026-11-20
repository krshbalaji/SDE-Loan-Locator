import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';

import '../models/borrower_model.dart';
import '../models/loan_model.dart';
import '../models/loan_product_model.dart';
import 'firestore_loan_service.dart';

class LocalVaultService {
  LocalVaultService._();

  static String serializeSnapshot(LoanPortfolioProvider portfolio) {
    final payload = <String, dynamic>{
      'schema': 'SDE_LOAN_LOCATOR_VAULT_V1',
      'exported_at': DateTime.now().toIso8601String(),
      'borrowers': portfolio.borrowers.map((b) => b.toMap()).toList(),
      'loan_products': portfolio.products.map((p) => p.toMap()).toList(),
      'loans': portfolio.loans.map((l) => l.toMap()).toList(),
      'transactions': portfolio.transactions.map((t) => t.toMap()).toList(),
      'collection_logs': portfolio.collectionLogs.map((c) => c.toMap()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Exports a portable JSON vault snapshot to local drive / downloads on Web & Mobile.
  static Future<void> exportVaultToLocalDrive(
    LoanPortfolioProvider portfolio,
  ) async {
    final jsonStr = serializeSnapshot(portfolio);
    final bytes = Uint8List.fromList(utf8.encode(jsonStr));
    final stamp = DateTime.now().toIso8601String().split('T').first;
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'SDE_Local_Vault_$stamp.json',
    );
  }

  /// Picks a `.json` local vault file and restores missing borrowers/products/loans.
  static Future<int> restoreVaultFromLocalDrive(
    LoanPortfolioProvider portfolio,
  ) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return 0;
    final bytes = picked.files.first.bytes;
    if (bytes == null) return 0;

    final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final existingLoanIds = portfolio.loans.map((l) => l.loanId).toSet();
    final existingBorrowerIds =
        portfolio.borrowers.map((b) => b.borrowerId).toSet();

    for (final raw in (decoded['loan_products'] as List<dynamic>? ?? const [])) {
      final prod = LoanProductModel.fromMap(raw as Map<String, dynamic>);
      if (portfolio.productById(prod.productId) == null) {
        await portfolio.saveProduct(prod);
      }
    }

    for (final raw in (decoded['borrowers'] as List<dynamic>? ?? const [])) {
      final b = BorrowerModel.fromMap(raw as Map<String, dynamic>);
      if (!existingBorrowerIds.contains(b.borrowerId)) {
        await portfolio.saveBorrower(b);
      }
    }

    var restoredCount = 0;
    for (final raw in (decoded['loans'] as List<dynamic>? ?? const [])) {
      final loan = LoanModel.fromMap(raw as Map<String, dynamic>);
      if (existingLoanIds.contains(loan.loanId)) continue;
      final b = portfolio.borrowerById(loan.borrowerId);
      final p = portfolio.productById(loan.productId) ??
          (portfolio.products.isNotEmpty ? portfolio.products.first : null);
      if (b != null && p != null) {
        await portfolio.originateNewLoan(
          borrower: b,
          product: p,
          principalSanctioned: loan.principalSanctioned,
          tenureInstallments: loan.tenureInstallments,
          collectedByUid: loan.assignedAgentId,
          customLoanId: loan.loanId,
          customApplicationNo: loan.applicationNo,
          disbursementDate: loan.disbursementDate,
        );
        restoredCount++;
      }
    }
    return restoredCount;
  }
}

