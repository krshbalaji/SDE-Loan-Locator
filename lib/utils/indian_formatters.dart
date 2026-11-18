import 'dart:math';

/// Indian compliance formatting & validation utilities for Saro Devi Enterprises.
/// Supports INR (₹) lakh/crore grouping, DD/MM/YYYY dates, GST splits, and KYC validators.
class IndianFormatters {
  IndianFormatters._();

  static final RegExp _panRegex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$');
  static final RegExp _gstinRegex = RegExp(
    r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$',
  );
  static final RegExp _ifscRegex = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
  static final RegExp _aadhaarMaskedRegex = RegExp(r'^XXXX-XXXX-[0-9]{4}$');

  /// Formats a rupee value using Indian numbering (e.g., ₹12,34,567.00 or ₹12,34,567).
  static String formatInr(double amount, {bool showDecimals = true}) {
    final isNegative = amount < 0;
    final absVal = amount.abs();
    final fixed = showDecimals
        ? absVal.toStringAsFixed(2)
        : absVal.round().toString();
    final parts = fixed.split('.');
    final intPart = parts[0];
    final decPart = parts.length > 1 ? '.${parts[1]}' : '';

    String formattedInt;
    if (intPart.length <= 3) {
      formattedInt = intPart;
    } else {
      final last3 = intPart.substring(intPart.length - 3);
      var rest = intPart.substring(0, intPart.length - 3);
      final chunks = <String>[];
      while (rest.length > 2) {
        chunks.insert(0, rest.substring(rest.length - 2));
        rest = rest.substring(0, rest.length - 2);
      }
      if (rest.isNotEmpty) {
        chunks.insert(0, rest);
      }
      formattedInt = '${chunks.join(',')},$last3';
    }

    return '${isNegative ? '-' : ''}₹$formattedInt$decPart';
  }

  /// Compact Indian currency format (e.g., ₹1.25 Cr, ₹4.50 L, ₹45.0 K).
  static String formatInrCompact(double amount) {
    final isNegative = amount < 0;
    final absVal = amount.abs();
    final sign = isNegative ? '-' : '';
    if (absVal >= 10000000) {
      return '$sign₹${(absVal / 10000000).toStringAsFixed(2)} Cr';
    } else if (absVal >= 100000) {
      return '$sign₹${(absVal / 100000).toStringAsFixed(2)} L';
    } else if (absVal >= 1000) {
      return '$sign₹${(absVal / 1000).toStringAsFixed(1)} K';
    }
    return formatInr(amount, showDecimals: false);
  }

  /// Formats date as DD/MM/YYYY.
  static String formatDate(DateTime date) {
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    final yyyy = date.year.toString().padLeft(4, '0');
    return '$dd/$mm/$yyyy';
  }

  /// Formats date + time as DD/MM/YYYY HH:mm.
  static String formatDateTime(DateTime date) {
    final hh = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    return '${formatDate(date)} $hh:$min';
  }

  /// Rounds money values to 2 decimal places (paise precision).
  static double roundPaise(double value) => (value * 100).roundToDouble() / 100;

  /// Computes 18% GST (or custom rate) on processing/penal fees.
  static ({double baseFee, double gstAmount, double totalFee}) computeFeeWithGst({
    required double baseFee,
    double gstRatePct = 18.0,
  }) {
    final roundedBase = roundPaise(max(0, baseFee));
    final gst = roundPaise(roundedBase * (gstRatePct / 100.0));
    return (
      baseFee: roundedBase,
      gstAmount: gst,
      totalFee: roundPaise(roundedBase + gst),
    );
  }

  /// Normalizes Indian mobile numbers into E.164 `+91XXXXXXXXXX`.
  static String normalizeIndianMobile(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10) {
      return '+91$digits';
    }
    if (digits.length == 12 && digits.startsWith('91')) {
      return '+$digits';
    }
    if (digits.length == 11 && digits.startsWith('0')) {
      return '+91${digits.substring(1)}';
    }
    if (digits.length > 10) {
      return '+91${digits.substring(digits.length - 10)}';
    }
    return raw.trim();
  }

  static bool isValidPan(String value) =>
      _panRegex.hasMatch(value.trim().toUpperCase());

  static bool isValidGstin(String value) =>
      _gstinRegex.hasMatch(value.trim().toUpperCase());

  static bool isValidIfsc(String value) =>
      _ifscRegex.hasMatch(value.trim().toUpperCase());

  static bool isValidMaskedAadhaar(String value) =>
      _aadhaarMaskedRegex.hasMatch(value.trim().toUpperCase());

  /// Masks a raw 12-digit Aadhaar into `XXXX-XXXX-1234`.
  static String maskAadhaar(String input) {
    final cleaned = input.trim().toUpperCase();
    if (_aadhaarMaskedRegex.hasMatch(cleaned)) return cleaned;
    final digits = cleaned.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 4) {
      final last4 = digits.substring(digits.length - 4);
      return 'XXXX-XXXX-$last4';
    }
    return cleaned;
  }

  /// Parses Firestore Timestamp (duck-typed), DateTime, epoch ms, or ISO string.
  static DateTime parseDate(dynamic value, {DateTime? fallback}) {
    if (value == null) return fallback ?? DateTime.now();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) {
      return DateTime.tryParse(value) ?? fallback ?? DateTime.now();
    }
    try {
      final dynamic converted = (value as dynamic).toDate();
      if (converted is DateTime) return converted;
    } catch (_) {}
    return fallback ?? DateTime.now();
  }

  static DateTime? parseNullableDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    try {
      final dynamic converted = (value as dynamic).toDate();
      if (converted is DateTime) return converted;
    } catch (_) {}
    return null;
  }
}
