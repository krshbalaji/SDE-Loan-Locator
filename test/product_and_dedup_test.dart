import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:loan_locator_app/models/borrower_model.dart';
import 'package:loan_locator_app/models/loan_product_model.dart';
import 'package:loan_locator_app/services/excel_import_service.dart';

void main() {
  group('DefaultLoanProducts presets', () {
    test('provides standard HF, LAP, Micro-LAP, and collections presets', () {
      expect(DefaultLoanProducts.catalog.length, 4);
      final ids = DefaultLoanProducts.catalog.map((p) => p.productId).toList();
      expect(
        ids,
        containsAll([
          'PROD_HF_HL',
          'PROD_LAP_STD',
          'PROD_LAP_MICRO',
          'PROD_COLL_DAILY',
        ]),
      );

      final lap = DefaultLoanProducts.primaryDefault;
      expect(lap.productId, 'PROD_LAP_STD');
      expect(lap.interestMethod, InterestMethod.reducingBalance);
      expect(lap.repaymentFrequency, RepaymentFrequency.monthly);
    });

    test('supports copyWith customization without mutating catalog defaults', () {
      final baseLap = DefaultLoanProducts.primaryDefault;
      final customized = baseLap.copyWith(
        productId: 'PROD_LAP_MADURAI_105',
        annualInterestRate: 10.5,
        maxTenureInstallments: 144,
        atRiskDpdThreshold: 45,
      );

      expect(customized.productId, 'PROD_LAP_MADURAI_105');
      expect(customized.annualInterestRate, 10.5);
      expect(customized.maxTenureInstallments, 144);
      expect(customized.atRiskDpdThreshold, 45);
      expect(baseLap.annualInterestRate, 12.0);
      expect(baseLap.maxTenureInstallments, 120);
    });
  });

  group('ExcelImportService deduplication and normalization', () {
    test('flags batch duplicate loanNo, normalizes mobile, and matches existing borrower', () {
      const csv =
          'LOAN_ID,APP_NO,APPLICANT_NAME,MOBILE_NO,SANCTION_AMOUNT,ROI,TENURE,BRANCH\n'
          'SDE-LN-9001,APP-9001,Karthikeyan M,9842199999,500000,12.0%,120,MADURAI\n'
          'SDE-LN-9001,APP-9002,Karthikeyan M Dup Loan,9842188888,450000,12.0%,120,MADURAI\n'
          'SDE-LN-9003,APP-9003,Existing Borrower,+919842177777,600000,12.0%,120,MADURAI';

      final existingBorrowers = [
        BorrowerModel(
          borrowerId: 'BOR-EXISTING-1',
          fullName: 'Existing Borrower',
          mobilePrimary: '+919842177777',
          addressText: 'Madurai',
          latitude: 9.9252,
          longitude: 78.1198,
          assignedAgentId: 'AGT-MDU-01',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      ];

      final res = ExcelImportService.parseCsvBytes(
        bytes: Uint8List.fromList(utf8.encode(csv)),
        fileName: 'batch_dedup_check.csv',
        existingBorrowers: existingBorrowers,
        existingLoans: const [],
      );

      expect(res.rows.length, 3);
      expect(res.duplicateLoanCount, 1);
      expect(res.duplicateBorrowerCount, 1);
      expect(res.rows[0].isDuplicateLoan, isFalse);
      expect(res.rows[0].isDuplicateBorrower, isFalse);
      expect(res.rows[0].mobilePrimary, '+919842199999');
      expect(res.rows[1].isDuplicateLoan, isTrue);
      expect(
        res.rows[1].warnings,
        contains('Duplicate LoanNo / ApplicationNo (skipped)'),
      );
      expect(res.rows[2].isDuplicateBorrower, isTrue);
      expect(
        res.rows[2].warnings,
        contains('Existing borrower matched by mobile'),
      );
    });
  });
}
