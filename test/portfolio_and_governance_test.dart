import 'package:flutter_test/flutter_test.dart';
import 'package:loan_locator_app/models/borrower_model.dart';
import 'package:loan_locator_app/models/loan_model.dart';
import 'package:loan_locator_app/models/loan_product_model.dart';
import 'package:loan_locator_app/models/user_model.dart';
import 'package:loan_locator_app/services/audit_service.dart';
import 'package:loan_locator_app/services/maker_checker_service.dart';
import 'package:loan_locator_app/utils/beat_route_planner.dart';
import 'package:loan_locator_app/utils/import_dry_run_validator.dart';
import 'package:loan_locator_app/utils/portfolio_intelligence.dart';
import 'package:loan_locator_app/utils/receipt_and_reminder.dart';

void main() {
  test('PortfolioIntelligence computes Sales, CE, NPA POS %, and diagnostics', () {
    final now = DateTime(2026, 11, 21);
    final borrowers = {
      'B1': BorrowerModel(
        borrowerId: 'B1',
        fullName: 'Karthik M',
        mobilePrimary: '9876543210',
        creditScore: 760,
        addressText: 'KK Nagar, Madurai',
        latitude: 9.9252,
        longitude: 78.1198,
        geoVerified: true,
        assignedAgentId: 'A1',
        createdAt: now,
        updatedAt: now,
      ),
      'B2': BorrowerModel(
        borrowerId: 'B2',
        fullName: 'Senthil R',
        mobilePrimary: '9876543211',
        creditScore: 630,
        addressText: 'Anna Nagar, Madurai',
        latitude: 0,
        longitude: 0,
        geoVerified: false,
        assignedAgentId: 'A1',
        createdAt: now,
        updatedAt: now,
      ),
    };

    final loans = [
      LoanModel(
        loanId: 'L1',
        applicationNo: 'APP1',
        borrowerId: 'B1',
        productId: 'HF-01',
        assignedAgentId: 'A1',
        principalSanctioned: 1200000,
        processingFeeAmount: 12000,
        gstAmount: 2160,
        netDisbursedAmount: 1185840,
        interestRateAnnual: 11.5,
        interestMethod: InterestMethod.reducingBalance,
        tenureInstallments: 84,
        emiAmount: 20000,
        disbursementDate: now.subtract(const Duration(days: 240)),
        firstDueDate: now.subtract(const Duration(days: 210)),
        maturityDate: now.add(const Duration(days: 2300)),
        principalOutstanding: 1000000,
        dpd: 0,
        agingBucket: AgingBucket.current,
        monthsOnBooks: 8,
        ltvPct: 60.0,
        foirPct: 38.0,
      ),
      LoanModel(
        loanId: 'L2',
        applicationNo: 'APP2',
        borrowerId: 'B2',
        productId: 'LAP-01',
        assignedAgentId: 'A1',
        principalSanctioned: 800000,
        processingFeeAmount: 8000,
        gstAmount: 1440,
        netDisbursedAmount: 790560,
        interestRateAnnual: 14.0,
        interestMethod: InterestMethod.reducingBalance,
        tenureInstallments: 48,
        emiAmount: 22000,
        disbursementDate: now.subtract(const Duration(days: 150)),
        firstDueDate: now.subtract(const Duration(days: 120)),
        maturityDate: now.add(const Duration(days: 1300)),
        principalOutstanding: 500000,
        dpd: 95,
        agingBucket: AgingBucket.dpd90Plus,
        monthsOnBooks: 5,
        ltvPct: 78.0,
        foirPct: 56.0,
      ),
    ];

    final summary = PortfolioIntelligence.analyze(
      loans: loans,
      borrowerMap: borrowers,
    );

    expect(summary.totalLoans, 2);
    expect(summary.npaLoans, 1);
    expect(summary.npaPos, 500000);
    expect(summary.npaPosPct, closeTo(33.3333, 0.01));
    expect(summary.salesKpiDiagnostic.whyPresented, isNotEmpty);
    expect(summary.npaScenarios.length, 4);
  });

  test('ImportDryRunValidator flags blank and duplicate loan IDs', () {
    final now = DateTime(2026, 11, 21);
    final sample = LoanModel(
      loanId: 'DUP-1',
      applicationNo: 'APP-DUP',
      borrowerId: 'B1',
      productId: 'HF-01',
      assignedAgentId: 'A1',
      principalSanctioned: 500000,
      processingFeeAmount: 5000,
      gstAmount: 900,
      netDisbursedAmount: 494100,
      interestRateAnnual: 12.0,
      interestMethod: InterestMethod.reducingBalance,
      tenureInstallments: 36,
      emiAmount: 16600,
      disbursementDate: now,
      firstDueDate: now.add(const Duration(days: 30)),
      maturityDate: now.add(const Duration(days: 1095)),
      principalOutstanding: 500000,
    );

    final report = ImportDryRunValidator.validateLoans(
      rows: [
        sample,
        sample.copyWith(loanId: '   '),
        sample,
      ],
    );

    expect(report.validLoans.length, 1);
    expect(report.invalidCount, 2);
    expect(report.issues.length, 2);
  });

  test('MakerCheckerService blocks four-eyes self-approval', () async {
    final audit = AuditService(useFirebase: false);
    final mc = MakerCheckerService(useFirebase: false, auditService: audit);

    final maker = AppUser(
      uid: 'u_maker',
      email: 'maker@sde.local',
      displayName: 'Maker One',
      role: UserRole.branchManager,
      isActive: true,
    );
    final checker = AppUser(
      uid: 'u_checker',
      email: 'checker@sde.local',
      displayName: 'Checker Two',
      role: UserRole.superAdmin,
      isActive: true,
    );

    final req = await mc.submitRequest(
      maker: maker,
      actionType: 'WAIVER_REQUEST',
      targetId: 'LN-101',
      amountInr: 5000,
      reason: 'Customer hardship adjustment',
    );

    final selfErr = await mc.decideRequest(
      checker: maker,
      requestId: req.id,
      approve: true,
    );
    expect(selfErr, isNotNull);
    expect(mc.requests.first.status, MakerCheckerStatus.pending);

    final okErr = await mc.decideRequest(
      checker: checker,
      requestId: req.id,
      approve: true,
      note: 'Verified',
    );
    expect(okErr, isNull);
    expect(mc.requests.first.status, MakerCheckerStatus.approved);
  });

  test('BeatRoutePlanner orders stops and ReceiptAndReminder formats Tamil & receipt', () {
    final now = DateTime(2026, 11, 21);
    final b1 = BorrowerModel(
      borrowerId: 'B1',
      fullName: 'Aravind K',
      mobilePrimary: '9876500001',
      addressText: 'Tallakulam, Madurai',
      latitude: 9.9350,
      longitude: 78.1280,
      geoVerified: true,
      assignedAgentId: 'A1',
      createdAt: now,
      updatedAt: now,
    );
    final b2 = BorrowerModel(
      borrowerId: 'B2',
      fullName: 'Meena S',
      mobilePrimary: '9876500002',
      addressText: 'No Coordinates',
      latitude: 0,
      longitude: 0,
      geoVerified: false,
      assignedAgentId: 'A1',
      createdAt: now,
      updatedAt: now,
    );
    final loan1 = LoanModel(
      loanId: 'LN-201',
      applicationNo: 'APP-201',
      borrowerId: 'B1',
      productId: 'HF-01',
      assignedAgentId: 'A1',
      principalSanctioned: 900000,
      processingFeeAmount: 9000,
      gstAmount: 1620,
      netDisbursedAmount: 889380,
      interestRateAnnual: 11.0,
      interestMethod: InterestMethod.reducingBalance,
      tenureInstallments: 60,
      emiAmount: 19500,
      disbursementDate: now,
      firstDueDate: now.add(const Duration(days: 30)),
      maturityDate: now.add(const Duration(days: 1800)),
      principalOutstanding: 850000,
      dpd: 18,
    );
    final loan2 = loan1.copyWith(loanId: 'LN-202', borrowerId: 'B2');

    final plan = BeatRoutePlanner.planRoute(
      loans: [loan1, loan2],
      borrowerMap: {'B1': b1, 'B2': b2},
    );
    expect(plan.stops.length, 1);
    expect(plan.skippedCount, 1);
    expect(plan.totalDistanceKm, greaterThan(0));

    final en = ReceiptAndReminder.buildEnglishReminder(loan: loan1, borrower: b1);
    final ta = ReceiptAndReminder.buildTamilReminder(loan: loan1, borrower: b1);
    final rcp = ReceiptAndReminder.buildDigitalReceipt(
      loan: loan1,
      borrower: b1,
      amountReceived: 19500,
      paymentMode: 'UPI',
      collectedBy: 'Field Agent',
    );
    expect(en, contains('LN-201'));
    expect(ta, contains('LN-201'));
    expect(rcp, contains('SDE-RCP-'));
  });
}
