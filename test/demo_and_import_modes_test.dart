import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:loan_locator_app/models/loan_product_model.dart';
import 'package:loan_locator_app/services/excel_import_service.dart';
import 'package:loan_locator_app/services/firestore_loan_service.dart';

void main() {
  const sampleProduct = LoanProductModel(
    productId: 'PROD_TEST_LAP',
    productName: 'LAP Test Product',
    interestMethod: InterestMethod.reducingBalance,
    annualInterestRate: 12.0,
    repaymentFrequency: RepaymentFrequency.monthly,
    maxTenureInstallments: 24,
  );

  test('clearAllData wipes seeded demo data and seedSamplePortfolio restores it', () async {
    final repo = InMemoryDemoLoanService();
    final provider = LoanPortfolioProvider(repository: repo, isDemoMode: true);
    await provider.refresh();

    expect(provider.borrowers.length, greaterThanOrEqualTo(2));
    expect(provider.loans.length, greaterThanOrEqualTo(2));

    repo.clearAllData();
    await provider.refresh();

    expect(provider.borrowers, isEmpty);
    expect(provider.loans, isEmpty);

    repo.seedSamplePortfolio();
    await provider.refresh();

    expect(provider.borrowers.length, greaterThanOrEqualTo(2));
    expect(provider.loans.length, greaterThanOrEqualTo(2));
  });

  test('commitImport supports Append and Overwrite modes cleanly', () async {
    final repo = InMemoryDemoLoanService();
    final provider = LoanPortfolioProvider(repository: repo, isDemoMode: true);
    await provider.refresh();

    final initialLoanCount = provider.loans.length;
    expect(initialLoanCount, greaterThan(0));

    final csvText = [
      'Location,ApplicationNo,LoanNo,CustomerName,Amount,LatLong,MobileNo',
      'Madurai,APP_NEW_901,LN_NEW_901,Senthil Kumar,450000,"9.9252, 78.1198",9842111122',
    ].join('\n');
    final bytes = Uint8List.fromList(utf8.encode(csvText));

    final parsed = ExcelImportService.parseCsvBytes(
      bytes: bytes,
      fileName: 'append_test.csv',
      existingBorrowers: provider.borrowers,
      existingLoans: provider.loans,
    );
    expect(parsed.validCount, 1);

    // Append mode keeps existing loans and adds the imported one
    final appendedCount = await ExcelImportService.commitImport(
      parseResult: parsed,
      portfolio: provider,
      defaultProduct: sampleProduct,
      assignedAgentId: 'uid_agent_karthik',
      importedByUid: 'uid_admin_meena',
      overwriteExisting: false,
    );
    expect(appendedCount, 1);
    expect(provider.loans.length, initialLoanCount + 1);

    // Overwrite mode clears prior loans and leaves only the newly imported loan
    final overwrittenCount = await ExcelImportService.commitImport(
      parseResult: parsed,
      portfolio: provider,
      defaultProduct: sampleProduct,
      assignedAgentId: 'uid_agent_karthik',
      importedByUid: 'uid_admin_meena',
      overwriteExisting: true,
    );
    expect(overwrittenCount, 1);
    expect(provider.loans.length, 1);
    expect(provider.loans.first.loanId, 'LN_NEW_901');
  });
}
