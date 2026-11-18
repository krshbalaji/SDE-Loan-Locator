import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

import '../engines/geo_filter_engine.dart';
import '../models/borrower_model.dart';
import '../models/loan_model.dart';
import '../models/loan_product_model.dart';
import '../utils/indian_formatters.dart';
import 'firestore_loan_service.dart';

class ExcelImportRow {
  const ExcelImportRow({
    required this.rowNumber,
    required this.location,
    required this.applicationNo,
    required this.loanNo,
    required this.customerName,
    required this.amount,
    required this.latitude,
    required this.longitude,
    required this.mobilePrimary,
    this.panNumber = '',
    this.tenureInstallments = 12,
    this.warnings = const [],
    this.isDuplicateBorrower = false,
    this.isDuplicateLoan = false,
  });

  final int rowNumber;
  final String location;
  final String applicationNo;
  final String loanNo;
  final String customerName;
  final double amount;
  final double? latitude;
  final double? longitude;
  final String mobilePrimary;
  final String panNumber;
  final int tenureInstallments;
  final List<String> warnings;
  final bool isDuplicateBorrower;
  final bool isDuplicateLoan;

  bool get isValid =>
      customerName.trim().isNotEmpty &&
      mobilePrimary.trim().isNotEmpty &&
      amount > 0 &&
      !isDuplicateLoan;
}

class ExcelParseResult {
  const ExcelParseResult({
    required this.fileName,
    required this.rows,
    required this.errors,
  });

  final String fileName;
  final List<ExcelImportRow> rows;
  final List<String> errors;

  int get validCount => rows.where((r) => r.isValid).length;
  int get duplicateLoanCount => rows.where((r) => r.isDuplicateLoan).length;
  int get duplicateBorrowerCount =>
      rows.where((r) => r.isDuplicateBorrower).length;
}

/// Upgraded Smart `.xlsx` Ingestion Pipeline.
/// Backward-compatible with the original 7-column sheet:
/// `Location`, `ApplicationNo`, `LoanNo`, `CustomerName`, `Amount`, `LatLong`, `MobileNo`
/// plus optional columns (`PAN`, `Tenure`).
class ExcelImportService {
  ExcelImportService._();

  static Future<ExcelParseResult?> pickAndParseExcel({
    required List<BorrowerModel> existingBorrowers,
    required List<LoanModel> existingLoans,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      return ExcelParseResult(
        fileName: file.name,
        rows: const [],
        errors: const ['Could not read file bytes from selected .xlsx file.'],
      );
    }

    return parseExcelBytes(
      bytes: bytes,
      fileName: file.name,
      existingBorrowers: existingBorrowers,
      existingLoans: existingLoans,
    );
  }

  /// Parses raw `.xlsx` bytes with header auto-detection (supports both 0-based and S.No-offset legacy sheets).
  static ExcelParseResult parseExcelBytes({
    required Uint8List bytes,
    required String fileName,
    required List<BorrowerModel> existingBorrowers,
    required List<LoanModel> existingLoans,
  }) {
    final errors = <String>[];
    final parsedRows = <ExcelImportRow>[];

    try {
      final excel = Excel.decodeBytes(bytes);
      final existingMobiles = {
        for (final b in existingBorrowers)
          IndianFormatters.normalizeIndianMobile(b.mobilePrimary),
      };
      final existingLoanIds = {
        for (final l in existingLoans) l.loanId.toUpperCase(),
      };
      final existingAppNos = {
        for (final l in existingLoans) l.applicationNo.toUpperCase(),
      };
      final seenLoanIds = <String>{};

      for (final tableName in excel.tables.keys) {
        final sheet = excel.tables[tableName];
        if (sheet == null || sheet.rows.isEmpty) continue;

        final headerCells = sheet.rows.first
            .map((c) => _cellText(c).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''))
            .toList();

        // Detect column indices dynamically, falling back to legacy 1..7 indexing.
        int colIdx(List<String> keys, int fallback) {
          for (var i = 0; i < headerCells.length; i++) {
            for (final k in keys) {
              if (headerCells[i].contains(k)) return i;
            }
          }
          return fallback;
        }

        final hasSerialCol =
            headerCells.isNotEmpty && (headerCells[0].contains('sno') || headerCells[0].contains('sl') || headerCells[0].isEmpty);
        final offset = hasSerialCol ? 1 : 0;

        final locIdx = colIdx(['location', 'address'], offset + 0);
        final appIdx = colIdx(['applicationno', 'appno'], offset + 1);
        final loanIdx = colIdx(['loanno', 'loanid'], offset + 2);
        final nameIdx = colIdx(['customername', 'fullname', 'name'], offset + 3);
        final amtIdx = colIdx(['amount', 'principal', 'sanctioned'], offset + 4);
        final latLngIdx = colIdx(['latlong', 'latlng', 'coordinates'], offset + 5);
        final mobileIdx = colIdx(['mobileno', 'mobile', 'phone'], offset + 6);
        final panIdx = colIdx(['pan'], -1);
        final tenureIdx = colIdx(['tenure', 'installments'], -1);

        for (var r = 1; r < sheet.rows.length; r++) {
          final row = sheet.rows[r];
          final name = _safeCell(row, nameIdx);
          final rawMobile = _safeCell(row, mobileIdx);
          final rawAmount = _safeCell(row, amtIdx);
          if (name.isEmpty && rawMobile.isEmpty && rawAmount.isEmpty) continue;

          final location = _safeCell(row, locIdx);
          final appNo = _safeCell(row, appIdx);
          final loanNo = _safeCell(row, loanIdx);
          final rawLatLng = _safeCell(row, latLngIdx);
          final pan = panIdx >= 0 ? _safeCell(row, panIdx).toUpperCase() : '';
          final tenure = tenureIdx >= 0
              ? (int.tryParse(_safeCell(row, tenureIdx)) ?? 12)
              : 12;

          final warnings = <String>[];
          final amount = double.tryParse(
                rawAmount.replaceAll(RegExp(r'[^0-9.]'), ''),
              ) ??
              0.0;
          if (amount <= 0) warnings.add('Invalid loan amount "$rawAmount"');

          final coords = GeoFilterEngine.parseLatLong(rawLatLng);
          if (coords == null) {
            warnings.add('Invalid or missing LatLong "$rawLatLng"');
          }

          final normalizedMobile =
              IndianFormatters.normalizeIndianMobile(rawMobile);
          if (normalizedMobile.length < 10) {
            warnings.add('Invalid mobile "$rawMobile"');
          }

          if (pan.isNotEmpty && !IndianFormatters.isValidPan(pan)) {
            warnings.add('Invalid PAN format "$pan"');
          }

          final normalizedLoanKey = loanNo.trim().toUpperCase();
          final normalizedAppKey = appNo.trim().toUpperCase();

          final isDupLoan = (normalizedLoanKey.isNotEmpty &&
                  (existingLoanIds.contains(normalizedLoanKey) ||
                      seenLoanIds.contains(normalizedLoanKey))) ||
              (normalizedAppKey.isNotEmpty &&
                  existingAppNos.contains(normalizedAppKey));

          if (normalizedLoanKey.isNotEmpty) {
            seenLoanIds.add(normalizedLoanKey);
          }

          final isDupBorrower = existingMobiles.contains(normalizedMobile);
          if (isDupLoan) warnings.add('Duplicate LoanNo / ApplicationNo (skipped)');
          if (isDupBorrower) warnings.add('Existing borrower matched by mobile');

          parsedRows.add(
            ExcelImportRow(
              rowNumber: r + 1,
              location: location,
              applicationNo: appNo,
              loanNo: loanNo,
              customerName: name,
              amount: amount,
              latitude: coords?.lat,
              longitude: coords?.lng,
              mobilePrimary: normalizedMobile,
              panNumber: pan,
              tenureInstallments: tenure.clamp(1, 120),
              warnings: warnings,
              isDuplicateBorrower: isDupBorrower,
              isDuplicateLoan: isDupLoan,
            ),
          );
        }
      }
    } catch (e) {
      errors.add('Failed to decode .xlsx file: $e');
    }

    return ExcelParseResult(
      fileName: fileName,
      rows: parsedRows,
      errors: errors,
    );
  }

  /// Commits validated rows into `borrowers`, `loans`, `installment_schedule`, and `transactions`.
  static Future<int> commitImport({
    required ExcelParseResult parseResult,
    required LoanPortfolioProvider portfolio,
    required LoanProductModel defaultProduct,
    required String assignedAgentId,
    required String importedByUid,
  }) async {
    var imported = 0;
    final now = DateTime.now();

    for (final row in parseResult.rows.where((r) => r.isValid)) {
      BorrowerModel? borrower;
      for (final existing in portfolio.borrowers) {
        if (IndianFormatters.normalizeIndianMobile(existing.mobilePrimary) ==
            row.mobilePrimary) {
          borrower = existing;
          break;
        }
      }

      if (borrower == null) {
        final lat = row.latitude ?? 9.9252;
        final lng = row.longitude ?? 78.1198;
        borrower = BorrowerModel(
          borrowerId: portfolio.generateNextBorrowerId(),
          fullName: row.customerName.trim(),
          mobilePrimary: row.mobilePrimary,
          panNumber: row.panNumber,
          addressText: row.location.isEmpty ? 'Madurai' : row.location,
          latitude: lat,
          longitude: lng,
          geohash: GeoFilterEngine.encodeGeohash(lat, lng),
          geoVerified: row.latitude != null && row.longitude != null,
          assignedAgentId: assignedAgentId,
          createdAt: now,
          updatedAt: now,
        );
        await portfolio.saveBorrower(borrower);
      }

      await portfolio.originateNewLoan(
        borrower: borrower,
        product: defaultProduct,
        principalSanctioned: row.amount,
        tenureInstallments: row.tenureInstallments,
        collectedByUid: importedByUid,
        customLoanId: row.loanNo.isNotEmpty ? row.loanNo : null,
        customApplicationNo:
            row.applicationNo.isNotEmpty ? row.applicationNo : null,
        disbursementDate: now,
      );
      imported++;
    }

    return imported;
  }

  static String _safeCell(List<Data?> row, int idx) {
    if (idx < 0 || idx >= row.length) return '';
    return _cellText(row[idx]);
  }

  static String _cellText(Data? cell) {
    final val = cell?.value;
    if (val == null) return '';
    return val.toString().trim();
  }
}
