import '../models/borrower_model.dart';
import '../models/loan_model.dart';
import 'indian_formatters.dart';

class ReceiptAndReminder {
  ReceiptAndReminder._();

  static String buildDigitalReceipt({
    required LoanModel loan,
    required BorrowerModel? borrower,
    required double amountReceived,
    required String paymentMode,
    required String collectedBy,
    String? receiptNo,
  }) {
    final now = DateTime.now();
    final code = receiptNo ??
        'SDE-RCP-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.millisecondsSinceEpoch.toString().substring(7)}';
    final name = borrower?.fullName ?? loan.borrowerId;
    final branch = borrower?.branch ?? 'Madurai HQ';
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    return [
      'SARO DEVI ENTERPRISES — DIGITAL RECEIPT',
      'Receipt No: $code',
      'Date/Time: $dateStr',
      'Borrower: $name (${loan.loanId})',
      'Branch: $branch',
      'Amount Received: ${IndianFormatters.formatInr(amountReceived)}',
      'Mode: $paymentMode',
      'Remaining POS: ${IndianFormatters.formatInr((loan.principalOutstanding - amountReceived).clamp(0, double.infinity))}',
      'Collected By: $collectedBy',
    ].join('\n');
  }

  static String buildEnglishReminder({
    required LoanModel loan,
    required BorrowerModel? borrower,
  }) {
    final name = borrower?.fullName ?? 'Customer';
    final dueAmt = IndianFormatters.formatInr(
      loan.emiAmount,
    );
    return 'Dear $name, friendly reminder for Loan ${loan.loanId} (DPD: ${loan.dpd} days). '
        'Due / Overdue Amount: $dueAmt. Please share payment / PTP confirmation with Saro Devi Enterprises field team.';
  }

  static String buildTamilReminder({
    required LoanModel loan,
    required BorrowerModel? borrower,
  }) {
    final name = borrower?.fullName ?? 'வாடிக்கையாளர்';
    final dueAmt = IndianFormatters.formatInr(
      loan.emiAmount,
    );
    return 'வணக்கம் $name, கடன் எண் ${loan.loanId} (DPD: ${loan.dpd} நாட்கள்) நிலுவைத் தொகை $dueAmt. '
        'கட்டண விவரம் அல்லது உறுதிப்படுத்திய தேதியை (PTP) சாரோ தேவி எண்டர்பிரைசஸ் களக் குழுவிடம் தெரிவிக்கவும்.';
  }
}

