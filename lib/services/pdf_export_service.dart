import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../engines/amortization_engine.dart';
import '../models/borrower_model.dart';
import '../models/installment_model.dart';
import '../models/loan_model.dart';
import '../models/loan_product_model.dart';
import '../models/transaction_model.dart';
import '../utils/indian_formatters.dart';

/// Generates Indian-compliant PDFs for Saro Devi Enterprises:
/// Payment Receipts, Key Fact Statements (KFS), Amortization Schedules, Payoff Quotes & Arrears Reports.
class PdfExportService {
  PdfExportService._();

  static const String _orgTitle = 'SARO DEVI ENTERPRISES (SPECIAL FINANCE UNIT)';
  static const String _orgSub = 'Madurai, Tamil Nadu | Lending & Collections Division';

  static String _pdfInr(double amount) =>
      IndianFormatters.formatInr(amount).replaceAll('₹', 'INR ');

  static pw.Widget _header(String documentTitle, String refNumber) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  _orgTitle,
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.indigo900,
                  ),
                ),
                pw.Text(
                  _orgSub,
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: pw.BoxDecoration(
                color: PdfColors.indigo50,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    documentTitle,
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.indigo900,
                    ),
                  ),
                  pw.Text(
                    'Ref: $refNumber',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Divider(color: PdfColors.indigo200, thickness: 1.5),
        pw.SizedBox(height: 8),
      ],
    );
  }

  /// Generates a Key Fact Statement (KFS) PDF including 18% GST fee breakdown & schedule summary.
  static Future<Uint8List> buildKeyFactStatementPdf({
    required BorrowerModel borrower,
    required LoanModel loan,
    required LoanProductModel product,
    required List<InstallmentModel> schedule,
  }) async {
    final doc = pw.Document();
    final activeRows = schedule
        .where((i) => i.scheduleVersion == loan.scheduleVersion)
        .toList()
      ..sort((a, b) => a.installmentNo.compareTo(b.installmentNo));
    final totalInterest =
        activeRows.fold<double>(0.0, (s, r) => s + r.interestDue);
    final totalPayable =
        IndianFormatters.roundPaise(loan.principalSanctioned + totalInterest);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          _header('KEY FACT STATEMENT (KFS)', loan.loanId),
          pw.Text(
            'Borrower Details',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerStyle:
                pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            data: [
              ['Borrower Name', borrower.fullName, 'Borrower ID', borrower.borrowerId],
              ['Mobile', borrower.mobilePrimary, 'PAN', borrower.panNumber.isEmpty ? 'N/A' : borrower.panNumber],
              ['Aadhaar (Masked)', borrower.aadhaarMasked.isEmpty ? 'N/A' : borrower.aadhaarMasked, 'GSTIN', borrower.gstin ?? 'N/A'],
              ['Address', borrower.addressText, 'Application No', loan.applicationNo],
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Key Financial Terms & Fee Disclosure (INR)',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            cellStyle: const pw.TextStyle(fontSize: 9),
            data: [
              ['Loan Product', product.productName],
              ['Sanctioned Principal', _pdfInr(loan.principalSanctioned)],
              ['Processing Fee (${product.processingFeePct}%)', _pdfInr(loan.processingFeeAmount)],
              ['GST on Processing Fee (${product.gstRatePct}%)', _pdfInr(loan.gstAmount)],
              ['Net Disbursed Amount', _pdfInr(loan.netDisbursedAmount)],
              ['Interest Rate & Method', '${loan.interestRateAnnual}% p.a. (${loan.interestMethod.label})'],
              ['Repayment Frequency & Tenure', '${loan.repaymentFrequency.label} x ${loan.tenureInstallments} installments'],
              ['Installment (EMI) Amount', _pdfInr(loan.emiAmount)],
              ['Total Interest Payable', _pdfInr(totalInterest)],
              ['Total Amount Payable', _pdfInr(totalPayable)],
              ['Grace Period / Late Fee', '${product.gracePeriodDays} days / ${product.lateFeeType == LateFeeType.flatInr ? _pdfInr(product.lateFeeValue) : "${product.lateFeeValue}% overdue"} + ${product.gstRatePct}% GST'],
              ['Disbursement / Maturity Date', '${IndianFormatters.formatDate(loan.disbursementDate)} to ${IndianFormatters.formatDate(loan.maturityDate)}'],
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Text(
            'Amortization Schedule (Version v${loan.scheduleVersion})',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo50),
            headerStyle:
                pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headers: ['#', 'Due Date', 'Opening Bal', 'Principal', 'Interest', 'Total Due', 'Status'],
            data: activeRows
                .map(
                  (r) => [
                    '${r.installmentNo}',
                    IndianFormatters.formatDate(r.dueDate),
                    _pdfInr(r.openingPrincipal),
                    _pdfInr(r.principalDue),
                    _pdfInr(r.interestDue),
                    _pdfInr(r.totalDue),
                    r.status.label,
                  ],
                )
                .toList(),
          ),
        ],
      ),
    );

    return doc.save();
  }

  /// Generates an official Payment Receipt PDF for an immutable ledger entry.
  static Future<Uint8List> buildPaymentReceiptPdf({
    required BorrowerModel borrower,
    required LoanModel loan,
    required TransactionModel txn,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _header('PAYMENT RECEIPT', txn.referenceNo),
            pw.Text(
              'Date: ${IndianFormatters.formatDateTime(txn.createdAt)}',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              cellStyle: const pw.TextStyle(fontSize: 10),
              data: [
                ['Transaction ID', txn.txnId],
                ['Loan Account', '${loan.loanId} (${loan.applicationNo})'],
                ['Borrower', '${borrower.fullName} (${borrower.mobilePrimary})'],
                ['Transaction Type', txn.txnType.label],
                ['Payment Mode', txn.paymentMode.label],
                ['Reference / UTR', txn.referenceNo],
                ['Total Amount Received', _pdfInr(txn.totalAmount)],
                ['Allocated to Fees/Penalties', _pdfInr(txn.allocatedFees)],
                ['Allocated to Interest', _pdfInr(txn.allocatedInterest)],
                ['Allocated to Principal', _pdfInr(txn.allocatedPrincipal)],
                ['Post-Payment Principal Balance', _pdfInr(loan.principalOutstanding)],
                ['Collected By (UID)', txn.collectedByUid],
              ],
            ),
            pw.SizedBox(height: 18),
            pw.Text(
              'This is a system-generated receipt from the immutable Saro Devi Enterprises ledger.',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  /// Generates a Foreclosure / Payoff Quote Letter PDF.
  static Future<Uint8List> buildPayoffQuotePdf({
    required BorrowerModel borrower,
    required LoanModel loan,
    required PayoffQuote quote,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _header('LOAN PAYOFF / FORECLOSURE QUOTE', loan.loanId),
            pw.Text(
              'Valid As Of: ${IndianFormatters.formatDate(quote.asOfDate)}',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'Dear ${borrower.fullName},',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'Below is the itemized payoff settlement figure for your loan account ${loan.loanId} with Saro Devi Enterprises (Special Finance Unit):',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              cellStyle: const pw.TextStyle(fontSize: 10),
              data: [
                ['Outstanding Principal', _pdfInr(quote.principalBalance)],
                ['Accrued Unpaid Interest', _pdfInr(quote.accruedInterest)],
                ['Unpaid Fees & Penalties', _pdfInr(quote.unpaidFees)],
                ['TOTAL PAYOFF AMOUNT', _pdfInr(quote.totalPayoffAmount)],
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              'Payment Rails Accepted: UPI, NEFT/RTGS, e-NACH, Cheque, or Verified Cash Receipt.',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  /// Generates a Portfolio Arrears Report PDF listing all delinquent accounts.
  static Future<Uint8List> buildArrearsReportPdf({
    required List<LoanModel> delinquentLoans,
    required Map<String, BorrowerModel> borrowerMap,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => [
          _header(
            'PORTFOLIO ARREARS & DPD REPORT',
            IndianFormatters.formatDate(DateTime.now()),
          ),
          pw.TableHelper.fromTextArray(
            headerDecoration: const pw.BoxDecoration(color: PdfColors.red50),
            headerStyle:
                pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headers: [
              'Loan ID',
              'Borrower',
              'Mobile',
              'DPD',
              'Bucket',
              'Principal Out.',
              'Total Out.',
              'EWS',
            ],
            data: delinquentLoans.map((l) {
              final b = borrowerMap[l.borrowerId];
              return [
                l.loanId,
                b?.fullName ?? l.borrowerId,
                b?.mobilePrimary ?? '-',
                '${l.dpd}',
                l.agingBucket.label,
                _pdfInr(l.principalOutstanding),
                _pdfInr(l.totalOutstanding),
                l.earlyWarningFlag ? 'YES' : 'NO',
              ];
            }).toList(),
          ),
        ],
      ),
    );
    return doc.save();
  }

  /// Shares or prints any generated PDF bytes via `printing`.
  static Future<void> shareOrPrintPdf(Uint8List bytes, String filename) async {
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }
}
