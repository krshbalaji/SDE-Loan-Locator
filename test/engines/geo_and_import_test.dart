import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_locator_app/engines/geo_filter_engine.dart';
import 'package:loan_locator_app/models/borrower_model.dart';
import 'package:loan_locator_app/models/loan_model.dart';
import 'package:loan_locator_app/models/loan_product_model.dart';
import 'package:loan_locator_app/services/excel_import_service.dart';

void main() {
  group('GeoFilterEngine & ExcelImportService', () {
    test('parses LatLong variants and encodes Geohash + Haversine distance', () {
      final parsed = GeoFilterEngine.parseLatLong('9.9252° N, 78.1198° E');
      expect(parsed, isNotNull);
      expect(parsed!.lat, closeTo(9.9252, 0.0001));
      expect(parsed.lng, closeTo(78.1198, 0.0001));

      final hash = GeoFilterEngine.encodeGeohash(parsed.lat, parsed.lng);
      expect(hash.length, 7);

      // Distance from Madurai HQ to Anna Nagar Madurai (~2.9 km)
      final dist = GeoFilterEngine.haversineDistanceKm(
        9.9252,
        78.1198,
        9.9225,
        78.1456,
      );
      expect(dist, inInclusiveRange(2.0, 4.0));
    });

    test('parses legacy 7-column .xlsx and deduplicates existing LoanNo & Borrower Mobile', () {
      final excel = Excel.createExcel();
      final sheet = excel[excel.getDefaultSheet()!];
      sheet.appendRow([
        TextCellValue('S.No'),
        TextCellValue('Location'),
        TextCellValue('ApplicationNo'),
        TextCellValue('LoanNo'),
        TextCellValue('CustomerName'),
        TextCellValue('Amount'),
        TextCellValue('LatLong'),
        TextCellValue('MobileNo'),
      ]);
      sheet.appendRow([
        IntCellValue(1),
        TextCellValue('West Masi St, Madurai'),
        TextCellValue('APP-5001'),
        TextCellValue('SDE-LN-5001'),
        TextCellValue('New Trader'),
        IntCellValue(150000),
        TextCellValue('9.9252, 78.1198'),
        TextCellValue('9842199999'),
      ]);
      // Duplicate LoanNo row
      sheet.appendRow([
        IntCellValue(2),
        TextCellValue('Anna Nagar'),
        TextCellValue('APP-2026-001'),
        TextCellValue('SDE-LN-2001'),
        TextCellValue('Existing Borrower'),
        IntCellValue(200000),
        TextCellValue('9.9225, 78.1456'),
        TextCellValue('9842111001'),
      ]);

      final encoded = excel.encode()!;
      final existingBorrowers = [
        BorrowerModel(
          borrowerId: 'SDE-CUST-1001',
          fullName: 'Existing Borrower',
          mobilePrimary: '+919842111001',
          addressText: 'Madurai',
          latitude: 9.9225,
          longitude: 78.1456,
          assignedAgentId: 'uid_agent_karthik',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      ];
      final existingLoans = [
        LoanModel(
          loanId: 'SDE-LN-2001',
          applicationNo: 'APP-2026-001',
          borrowerId: 'SDE-CUST-1001',
          productId: 'PROD-QBL',
          assignedAgentId: 'uid_agent_karthik',
          principalSanctioned: 200000,
          processingFeeAmount: 4000,
          gstAmount: 720,
          netDisbursedAmount: 195280,
          interestRateAnnual: 24,
          interestMethod: InterestMethod.reducingBalance,
          tenureInstallments: 12,
          emiAmount: 18912,
          disbursementDate: DateTime(2026, 1, 1),
          firstDueDate: DateTime(2026, 2, 1),
          maturityDate: DateTime(2027, 1, 1),
          principalOutstanding: 200000,
        ),
      ];

      final result = ExcelImportService.parseExcelBytes(
        bytes: Uint8List.fromList(encoded),
        fileName: 'madurai_batch.xlsx',
        existingBorrowers: existingBorrowers,
        existingLoans: existingLoans,
      );

      expect(result.errors, isEmpty);
      expect(result.rows.length, 2);
      expect(result.validCount, 1);
      expect(result.duplicateLoanCount, 1);
      expect(result.duplicateBorrowerCount, 1);
      expect(result.rows.first.mobilePrimary, '+919842199999');
      expect(result.rows.first.latitude, closeTo(9.9252, 0.0001));
    });
  });
}

