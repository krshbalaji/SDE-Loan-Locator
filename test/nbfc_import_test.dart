import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:loan_locator_app/services/excel_import_service.dart';

void main() {
  test('Parses NBFC master CSV headers with MOB, ROI, PAN, and LatLong', () {
    const csv = 'LOAN_ID,APP_NO,APPLICANT_NAME,MOBILE_NO,PAN_NO,SANCTION_AMOUNT,ROI,TENURE,MOB,DPD,PROPERTY_LATLONG,BRANCH,PINCODE\n'
        'SDE-LN-9001,APP-9001,Karthikeyan M,9842199999,ABCDE1234F,500000,14.5%,24,4,0,"9.9252,78.1198",MADURAI,625001';

    final res = ExcelImportService.parseCsvBytes(
      bytes: Uint8List.fromList(utf8.encode(csv)),
      fileName: 'nbfc_master.csv',
      existingBorrowers: const [],
      existingLoans: const [],
    );

    expect(res.errors, isEmpty);
    expect(res.validCount, 1);
    final row = res.rows.first;
    expect(row.loanNo, 'SDE-LN-9001');
    expect(row.customerName, 'Karthikeyan M');
    expect(row.mobilePrimary, '+919842199999');
    expect(row.amount, 500000.0);
    expect(row.customRoi, 14.5);
    expect(row.tenureInstallments, 24);
    expect(row.monthsOnBooks, 4);
    expect(row.latitude, closeTo(9.9252, 0.0001));
    expect(row.branch, 'MADURAI');
  });
}
