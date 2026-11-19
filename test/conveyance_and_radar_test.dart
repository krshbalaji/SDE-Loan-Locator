import 'package:flutter_test/flutter_test.dart';
import 'package:loan_locator_app/engines/conveyance_engine.dart';
import 'package:loan_locator_app/engines/geo_filter_engine.dart';
import 'package:loan_locator_app/models/borrower_model.dart';
import 'package:loan_locator_app/models/collection_log_model.dart';
import 'package:loan_locator_app/models/loan_model.dart';
import 'package:loan_locator_app/models/loan_product_model.dart';
import 'package:loan_locator_app/models/transaction_model.dart';

void main() {
  test('ConveyanceEngine computes verified road km & reimbursement automatically', () {
    final day = DateTime(2026, 11, 19, 10, 0);
    final borrowers = [
      BorrowerModel(
        borrowerId: 'B1',
        fullName: 'West Masi Borrower',
        mobilePrimary: '9842100001',
        addressText: 'West Masi St, Madurai',
        latitude: 9.9195,
        longitude: 78.1193,
        assignedAgentId: 'AGT1',
        createdAt: day,
        updatedAt: day,
      ),
      BorrowerModel(
        borrowerId: 'B2',
        fullName: 'Anna Nagar Borrower',
        mobilePrimary: '9842100002',
        addressText: 'Anna Nagar, Madurai',
        latitude: 9.9225,
        longitude: 78.1456,
        assignedAgentId: 'AGT1',
        createdAt: day,
        updatedAt: day,
      ),
    ];

    final logs = [
      CollectionLogModel(
        logId: 'L1',
        loanId: 'LN1',
        borrowerId: 'B1',
        agentId: 'AGT1',
        actionType: CollectionActionType.fieldVisit,
        disposition: CollectionDisposition.ptpConfirmed,
        visitLat: 9.9196,
        visitLng: 78.1194,
        notes: 'Visited shop',
        nextFollowupAt: day.add(const Duration(days: 2)),
        createdAt: day,
      ),
    ];

    final txns = [
      TransactionModel(
        txnId: 'T1',
        loanId: 'LN2',
        borrowerId: 'B2',
        txnType: TransactionType.repayment,
        paymentMode: PaymentMode.upi,
        referenceNo: 'UTR123',
        totalAmount: 15000,
        collectedByUid: 'AGT1',
        geoLat: 9.9225,
        geoLng: 78.1456,
        createdAt: day.add(const Duration(hours: 1)),
      ),
    ];

    final res = ConveyanceEngine.computePeriodConveyance(
      logs: logs,
      transactions: txns,
      borrowers: borrowers,
      agentNames: {'AGT1': 'Karthik Raja'},
      fromDate: DateTime(2026, 11, 1),
      toDate: DateTime(2026, 11, 30),
      ratePerKmInr: 5.0,
    );

    expect(res.length, 1);
    expect(res.first.verifiedOnSiteStops, 2);
    expect(res.first.verifiedRoadKm, greaterThan(3.0));
    expect(res.first.reimbursementInr, greaterThan(15.0));
    expect(res.first.collectionPerKmInr, greaterThan(3000.0));
  });

  test('Customer-anchored radius scales from 5 km urban to 75 km district', () {
    final day = DateTime(2026, 1, 1);
    final borrowers = [
      BorrowerModel(
        borrowerId: 'ANCHOR',
        fullName: 'Madurai Anchor',
        mobilePrimary: '9842100001',
        addressText: 'Madurai',
        latitude: 9.9195,
        longitude: 78.1193,
        assignedAgentId: 'AGT1',
        createdAt: day,
        updatedAt: day,
      ),
      BorrowerModel(
        borrowerId: 'NEAR',
        fullName: 'Anna Nagar',
        mobilePrimary: '9842100002',
        addressText: 'Madurai',
        latitude: 9.9225,
        longitude: 78.1456,
        assignedAgentId: 'AGT1',
        createdAt: day,
        updatedAt: day,
      ),
      BorrowerModel(
        borrowerId: 'SIVAKASI',
        fullName: 'Sivakasi Unit',
        mobilePrimary: '9842100003',
        addressText: 'Sivakasi',
        latitude: 9.4533,
        longitude: 77.8024,
        assignedAgentId: 'AGT1',
        createdAt: day,
        updatedAt: day,
      ),
    ];

    final loans = borrowers
        .map(
          (b) => LoanModel(
            loanId: 'LN-${b.borrowerId}',
            applicationNo: 'APP-${b.borrowerId}',
            borrowerId: b.borrowerId,
            productId: 'P1',
            assignedAgentId: 'AGT1',
            principalSanctioned: 100000,
            interestMethod: InterestMethod.reducingBalance,
            interestRateAnnual: 18.0,
            tenureInstallments: 12,
            emiAmount: 9168,
            processingFeeAmount: 2000,
            gstAmount: 360,
            netDisbursedAmount: 97640,
            disbursementDate: day,
            firstDueDate: DateTime(2026, 2, 1),
            maturityDate: DateTime(2027, 1, 1),
            principalOutstanding: 80000,
          ),
        )
        .toList();

    final within5Km = GeoFilterEngine.filterPins(
      borrowers: borrowers,
      loans: loans,
      logs: const [],
      originLat: 9.9195,
      originLng: 78.1193,
      maxRadiusKm: 5.0,
    );
    expect(within5Km.map((p) => p.borrower.borrowerId), contains('NEAR'));
    expect(within5Km.map((p) => p.borrower.borrowerId), isNot(contains('SIVAKASI')));

    final within75Km = GeoFilterEngine.filterPins(
      borrowers: borrowers,
      loans: loans,
      logs: const [],
      originLat: 9.9195,
      originLng: 78.1193,
      maxRadiusKm: 75.0,
    );
    expect(within75Km.map((p) => p.borrower.borrowerId), contains('SIVAKASI'));
  });
}
