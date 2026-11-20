import 'dart:convert';
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
    this.coApplicantName,
    required this.amount,
    required this.latitude,
    required this.longitude,
    required this.mobilePrimary,
    this.panNumber = '',
    this.aadhaarMasked = '',
    this.ckycId,
    this.cersaiId,
    this.creditScore,
    this.branch,
    this.pincode,
    this.tenureInstallments = 12,
    this.customRoi,
    this.monthsOnBooks,
    this.dpd,
    this.principalOutstandingOverride,
    this.ltvPct,
    this.foirPct,
    this.assetClassification,
    this.lastPaidDate,
    this.warnings = const [],
    this.isDuplicateBorrower = false,
    this.isDuplicateLoan = false,
    this.isClosedOrRejected = false,
  });

  final int rowNumber;
  final String location;
  final String applicationNo;
  final String loanNo;
  final String customerName;
  final String? coApplicantName;
  final double amount;
  final double? latitude;
  final double? longitude;
  final String mobilePrimary;
  final String panNumber;
  final String aadhaarMasked;
  final String? ckycId;
  final String? cersaiId;
  final int? creditScore;
  final String? branch;
  final String? pincode;
  final int tenureInstallments;
  final double? customRoi;
  final int? monthsOnBooks;
  final int? dpd;
  final double? principalOutstandingOverride;
  final double? ltvPct;
  final double? foirPct;
  final String? assetClassification;
  final DateTime? lastPaidDate;
  final List<String> warnings;
  final bool isDuplicateBorrower;
  final bool isDuplicateLoan;
  final bool isClosedOrRejected;

  bool get isValid =>
      customerName.trim().isNotEmpty &&
      mobilePrimary.trim().isNotEmpty &&
      amount > 0 &&
      !isDuplicateLoan &&
      !isClosedOrRejected;
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
  int get closedOrRejectedCount =>
      rows.where((r) => r.isClosedOrRejected).length;
}

/// Content-Aware + Dual-Schema `.xlsx` and `.csv` Bulk Ingestion Pipeline.
/// Combines header-alias matching with cell-content pattern inference (detecting
/// `lat, lng` coordinates, 10-digit Indian mobiles, PAN IDs, amounts, and names
/// regardless of header naming or column order).
class ExcelImportService {
  ExcelImportService._();

  static Future<ExcelParseResult?> pickAndParseExcel({
    required List<BorrowerModel> existingBorrowers,
    required List<LoanModel> existingLoans,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      return ExcelParseResult(
        fileName: file.name,
        rows: const [],
        errors: const ['Could not read file bytes from selected file.'],
      );
    }

    if (file.name.toLowerCase().endsWith('.csv')) {
      return parseCsvBytes(
        bytes: bytes,
        fileName: file.name,
        existingBorrowers: existingBorrowers,
        existingLoans: existingLoans,
      );
    }

    return parseExcelBytes(
      bytes: bytes,
      fileName: file.name,
      existingBorrowers: existingBorrowers,
      existingLoans: existingLoans,
    );
  }

  /// Parses `.csv` bytes into [ExcelParseResult].
  static ExcelParseResult parseCsvBytes({
    required Uint8List bytes,
    required String fileName,
    required List<BorrowerModel> existingBorrowers,
    required List<LoanModel> existingLoans,
  }) {
    final errors = <String>[];
    final parsedRows = <ExcelImportRow>[];
    try {
      final text = utf8.decode(bytes, allowMalformed: true);
      final rawLines = const LineSplitter()
          .convert(text)
          .where((l) => l.trim().isNotEmpty)
          .toList();
      if (rawLines.isEmpty) {
        return ExcelParseResult(
          fileName: fileName,
          rows: const [],
          errors: const ['CSV file is empty.'],
        );
      }
      final grid = rawLines.map(_splitCsvLine).toList();
      parsedRows.addAll(
        _parseMatrix(
          grid: grid,
          existingBorrowers: existingBorrowers,
          existingLoans: existingLoans,
        ),
      );
    } catch (e) {
      errors.add('Failed to parse .csv file: $e');
    }
    return ExcelParseResult(
      fileName: fileName,
      rows: parsedRows,
      errors: errors,
    );
  }

  /// Parses raw `.xlsx` bytes with content-aware + header auto-detection.
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
      for (final tableName in excel.tables.keys) {
        final sheet = excel.tables[tableName];
        if (sheet == null || sheet.rows.isEmpty) continue;
        final grid = sheet.rows
            .map((r) => r.map((c) => _cellText(c)).toList())
            .toList();
        parsedRows.addAll(
          _parseMatrix(
            grid: grid,
            existingBorrowers: existingBorrowers,
            existingLoans: existingLoans,
          ),
        );
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

  /// Scores column cell contents across sample rows to infer missing/renamed headers.
  static int _inferColumnByContent(
    List<List<String>> grid,
    bool Function(String val) matcher, {
    Set<int> excludeCols = const {},
  }) {
    if (grid.length <= 1) return -1;
    final sampleLimit = grid.length < 25 ? grid.length : 25;
    var bestCol = -1;
    var bestHits = 0;

    final maxCols = grid.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    for (var col = 0; col < maxCols; col++) {
      if (excludeCols.contains(col)) continue;
      var hits = 0;
      var nonEmpty = 0;
      for (var r = 1; r < sampleLimit; r++) {
        if (col >= grid[r].length) continue;
        final v = grid[r][col].trim();
        if (v.isEmpty || v.toUpperCase() == 'N/A') continue;
        nonEmpty++;
        if (matcher(v)) hits++;
      }
      if (nonEmpty > 0 && hits > bestHits && (hits / nonEmpty) >= 0.4) {
        bestHits = hits;
        bestCol = col;
      }
    }
    return bestCol;
  }

  static List<ExcelImportRow> _parseMatrix({
    required List<List<String>> grid,
    required List<BorrowerModel> existingBorrowers,
    required List<LoanModel> existingLoans,
  }) {
    if (grid.isEmpty) return const [];

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

    final headerCells = grid.first
        .map((c) => c.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .toList();

    int colExactOrContains(
      List<String> exactKeys,
      List<String> partialKeys,
      int fallback,
    ) {
      for (var i = 0; i < headerCells.length; i++) {
        if (exactKeys.contains(headerCells[i])) return i;
      }
      for (var i = 0; i < headerCells.length; i++) {
        for (final k in partialKeys) {
          if (headerCells[i].contains(k)) return i;
        }
      }
      return fallback;
    }

    final isNbfcMaster = headerCells.contains('loanid') ||
        headerCells.contains('applicantname') ||
        headerCells.contains('sanctionamount') ||
        headerCells.contains('totaldisbursedamount');

    final hasSerialCol = !isNbfcMaster &&
        headerCells.isNotEmpty &&
        (headerCells[0].contains('sno') ||
            headerCells[0].contains('sl') ||
            headerCells[0].isEmpty);
    final offset = hasSerialCol ? 1 : 0;

    var latLngIdx = colExactOrContains(
      ['propertylatlong', 'latlong', 'latlng', 'coordinates'],
      ['latlong', 'latlng'],
      -1,
    );
    if (latLngIdx < 0) {
      latLngIdx = _inferColumnByContent(
        grid,
        (v) => GeoFilterEngine.parseLatLong(v) != null,
      );
    }
    if (latLngIdx < 0 && !isNbfcMaster) latLngIdx = offset + 5;

    var mobileIdx = colExactOrContains(
      ['mobileno', 'mobile', 'phone', 'primarymobile'],
      ['mobileno', 'mobile'],
      -1,
    );
    if (mobileIdx < 0) {
      mobileIdx = _inferColumnByContent(
        grid,
        (v) =>
            RegExp(r'^(?:\+?91)?[6-9]\d{9}$')
                .hasMatch(v.replaceAll(RegExp(r'[\s\-]'), '')),
        excludeCols: {latLngIdx},
      );
    }
    if (mobileIdx < 0 && !isNbfcMaster) mobileIdx = offset + 6;

    var panIdx = colExactOrContains(['panno', 'pan'], ['panno'], -1);
    if (panIdx < 0) {
      panIdx = _inferColumnByContent(
        grid,
        (v) => IndianFormatters.isValidPan(v.toUpperCase()),
        excludeCols: {latLngIdx, mobileIdx},
      );
    }

    var amtIdx = colExactOrContains(
      ['totaldisbursedamount', 'sanctionamount', 'amount', 'principal'],
      ['disbursedamount', 'sanctionamount', 'amount'],
      -1,
    );
    if (amtIdx < 0) {
      amtIdx = _inferColumnByContent(
        grid,
        (v) {
          final n = _parseDouble(v);
          return n != null && n >= 10000 && !v.contains(',') && v.length <= 10;
        },
        excludeCols: {latLngIdx, mobileIdx, panIdx},
      );
    }
    if (amtIdx < 0 && !isNbfcMaster) amtIdx = offset + 4;

    var nameIdx = colExactOrContains(
      ['applicantname', 'customername', 'fullname', 'name'],
      ['applicantname', 'customername'],
      -1,
    );
    if (nameIdx < 0) {
      nameIdx = _inferColumnByContent(
        grid,
        (v) =>
            RegExp(r'^[A-Za-z][A-Za-z\s\.]{3,40}$').hasMatch(v) &&
            !v.toLowerCase().contains('madurai') &&
            !v.toLowerCase().contains('india'),
        excludeCols: {latLngIdx, mobileIdx, panIdx, amtIdx},
      );
    }
    if (nameIdx < 0 && !isNbfcMaster) nameIdx = offset + 3;

    final locIdx = colExactOrContains(
      ['location', 'address', 'village', 'district'],
      ['location', 'address'],
      isNbfcMaster ? -1 : offset + 0,
    );
    final villageIdx = colExactOrContains(['village'], [], -1);
    final districtIdx = colExactOrContains(['district'], [], -1);
    final branchIdx = colExactOrContains(['branch'], [], -1);
    final pincodeIdx = colExactOrContains(['pincode', 'pin'], [], -1);
    final statusIdx = colExactOrContains(['currentstatus', 'runstatus', 'status'], [], -1);

    final appIdx = colExactOrContains(
      ['appno', 'applicationno', 'partnerapplicationno'],
      ['applicationno', 'appno'],
      isNbfcMaster ? -1 : offset + 1,
    );
    final loanIdx = colExactOrContains(
      ['loanid', 'loanno'],
      ['loanno', 'loanid'],
      isNbfcMaster ? -1 : offset + 2,
    );
    final coAppIdx = colExactOrContains(
      ['coapplicantname', 'coapplicant'],
      ['coapplicant'],
      -1,
    );

    final uidIdx = colExactOrContains(['uidno', 'aadhaar', 'aadhar'], [], -1);
    final ckycIdx = colExactOrContains(['ckycid', 'ckyc'], [], -1);
    final cersaiIdx = colExactOrContains(['cersaiid', 'cersai'], [], -1);
    final scoreIdx = colExactOrContains(
      ['maxcreditscore', 'creditscore', 'cibil'],
      ['creditscore'],
      -1,
    );
    final roiIdx = colExactOrContains(['roi', 'sroi', 'interestrate'], [], -1);
    final tenureIdx = colExactOrContains(
      ['tenure', 'tenureinstallments', 'installments'],
      ['tenure'],
      -1,
    );
    final mobIdx = colExactOrContains(['mob', 'monthsonbooks'], [], -1);
    final dpdIdx = colExactOrContains(['dpd', 'dpdasperos'], [], -1);
    final posIdx = colExactOrContains(
      ['pos', 'principaloutstanding', 'calcpos'],
      [],
      -1,
    );
    final ltvIdx = colExactOrContains(['ltv'], [], -1);
    final foirIdx = colExactOrContains(['foir'], [], -1);
    final assetClassIdx = colExactOrContains(
      ['assetclassificationasperos', 'assetclassification'],
      ['assetclass'],
      -1,
    );
    final lastPaidIdx = colExactOrContains(['datelastpaid', 'lastpaiddate'], [], -1);

    final parsedRows = <ExcelImportRow>[];
    for (var r = 1; r < grid.length; r++) {
      final row = grid[r];
      final name = _safeStr(row, nameIdx);
      final rawMobile = _safeStr(row, mobileIdx);
      final rawAmount = _safeStr(row, amtIdx);
      if (name.isEmpty && rawMobile.isEmpty && rawAmount.isEmpty) continue;

      final rawStatus =
          statusIdx >= 0 ? _safeStr(row, statusIdx).toLowerCase() : '';
      final isClosedOrRejected = rawStatus.contains('foreclos') ||
          rawStatus.contains('closed') ||
          rawStatus.contains('not sanction') ||
          rawStatus.contains('reject') || _safeStr(row, loanIdx).toLowerCase().contains('not aprove');

      final branch = branchIdx >= 0 ? _safeStr(row, branchIdx) : '';
      final pincode = pincodeIdx >= 0 ? _safeStr(row, pincodeIdx) : '';
      final village = villageIdx >= 0 ? _safeStr(row, villageIdx) : '';
      final district = districtIdx >= 0 ? _safeStr(row, districtIdx) : '';

      var location = _safeStr(row, locIdx);
      if (location.isEmpty) {
        location = [village, district, branch, pincode]
            .where((p) => p.isNotEmpty && p.toUpperCase() != 'N/A')
            .join(', ');
      }

      final appNo = _safeStr(row, appIdx);
      final loanNo = _safeStr(row, loanIdx);
      final coApp = coAppIdx >= 0 ? _safeStr(row, coAppIdx) : '';
      final rawLatLng = _safeStr(row, latLngIdx);
      final pan = panIdx >= 0 ? _safeStr(row, panIdx).toUpperCase() : '';
      final rawUid = uidIdx >= 0 ? _safeStr(row, uidIdx) : '';
      final maskedUid = _maskGovernmentId(rawUid);
      final ckyc = ckycIdx >= 0 ? _safeStr(row, ckycIdx) : '';
      final cersai = cersaiIdx >= 0 ? _safeStr(row, cersaiIdx) : '';
      final creditScore =
          scoreIdx >= 0 ? int.tryParse(_digitsOnly(_safeStr(row, scoreIdx))) : null;

      final tenure = tenureIdx >= 0
          ? (int.tryParse(_digitsOnly(_safeStr(row, tenureIdx))) ?? 12)
          : 12;
      final customRoi = roiIdx >= 0 ? _parseDouble(_safeStr(row, roiIdx)) : null;
      final mob = mobIdx >= 0 ? int.tryParse(_digitsOnly(_safeStr(row, mobIdx))) : null;
      final dpd = dpdIdx >= 0 ? int.tryParse(_signedDigits(_safeStr(row, dpdIdx))) : null;
      final pos = posIdx >= 0 ? _parseDouble(_safeStr(row, posIdx)) : null;
      final ltv = ltvIdx >= 0 ? _parseDouble(_safeStr(row, ltvIdx)) : null;
      final foir = foirIdx >= 0 ? _parseDouble(_safeStr(row, foirIdx)) : null;
      final assetClass =
          assetClassIdx >= 0 ? _safeStr(row, assetClassIdx) : '';
      final rawLastPaid = lastPaidIdx >= 0 ? _safeStr(row, lastPaidIdx) : '';
      final lastPaid =
          rawLastPaid.isNotEmpty && rawLastPaid.toUpperCase() != 'N/A'
              ? IndianFormatters.parseDate(rawLastPaid)
              : null;

      final warnings = <String>[];
      if (isClosedOrRejected) {
        warnings.add('Status "${_safeStr(row, statusIdx)}" (skipped from active portfolio)');
      }

      final amount = _parseDouble(rawAmount) ?? 0.0;
      if (amount <= 0 && !isClosedOrRejected) {
        warnings.add('Invalid loan amount "$rawAmount"');
      }

      final coords = GeoFilterEngine.parseLatLong(rawLatLng);
      if (coords == null) {
        warnings.add('Invalid or missing LatLong "$rawLatLng"');
      }

      final normalizedMobile = IndianFormatters.normalizeIndianMobile(rawMobile);
      if (normalizedMobile.length < 10) {
        warnings.add('Invalid mobile "$rawMobile"');
      }

      if (pan.isNotEmpty && pan != 'N/A' && !IndianFormatters.isValidPan(pan)) {
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
          coApplicantName:
              coApp.isEmpty || coApp.toUpperCase() == 'N/A' ? null : coApp,
          amount: amount,
          latitude: coords?.lat,
          longitude: coords?.lng,
          mobilePrimary: normalizedMobile,
          panNumber: pan == 'N/A' ? '' : pan,
          aadhaarMasked: maskedUid,
          ckycId: ckyc.isEmpty || ckyc.toUpperCase() == 'N/A' ? null : ckyc,
          cersaiId:
              cersai.isEmpty || cersai.toUpperCase() == 'N/A' ? null : cersai,
          creditScore: creditScore,
          branch: branch.isEmpty || branch.toUpperCase() == 'N/A' ? null : branch,
          pincode:
              pincode.isEmpty || pincode.toUpperCase() == 'N/A' ? null : pincode,
          tenureInstallments: tenure.clamp(1, 360),
          customRoi: customRoi,
          monthsOnBooks: mob,
          dpd: dpd,
          principalOutstandingOverride: pos,
          ltvPct: ltv,
          foirPct: foir,
          assetClassification: assetClass.isEmpty ||
                  assetClass.toUpperCase() == 'N/A'
              ? null
              : assetClass,
          lastPaidDate: lastPaid,
          warnings: warnings,
          isDuplicateBorrower: isDupBorrower,
          isDuplicateLoan: isDupLoan,
          isClosedOrRejected: isClosedOrRejected,
        ),
      );
    }

    return parsedRows;
  }

  /// Commits validated active rows into `borrowers`, `loans`, `installment_schedule`, and `transactions`.
  /// Preserves imported `MOB`, `DPD`, `agingBucket`, and `POS` from NBFC master datasets.
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
          coApplicantName: row.coApplicantName,
          mobilePrimary: row.mobilePrimary,
          panNumber: row.panNumber,
          aadhaarMasked: row.aadhaarMasked,
          ckycId: row.ckycId,
          cersaiId: row.cersaiId,
          creditScore: row.creditScore,
          branch: row.branch,
          pincode: row.pincode,
          addressText: row.location.isEmpty ? 'Madurai' : row.location,
          latitude: lat,
          longitude: lng,
          geohash: GeoFilterEngine.encodeGeohash(lat, lng),
          geoVerified: row.latitude != null && row.longitude != null,
          assignedAgentId: assignedAgentId,
          createdAt: now,
          updatedAt: now,
        );
        await portfolio.saveBorrower(borrower, skipRefresh: true);
      }

      final effectiveProduct = row.customRoi != null && row.customRoi! > 0
          ? LoanProductModel(
              productId: defaultProduct.productId,
              productName: defaultProduct.productName,
              interestMethod: defaultProduct.interestMethod,
              annualInterestRate: row.customRoi!,
              repaymentFrequency: defaultProduct.repaymentFrequency,
              maxTenureInstallments: defaultProduct.maxTenureInstallments,
              processingFeePct: defaultProduct.processingFeePct,
              gstRatePct: defaultProduct.gstRatePct,
              gracePeriodDays: defaultProduct.gracePeriodDays,
              lateFeeType: defaultProduct.lateFeeType,
              lateFeeValue: defaultProduct.lateFeeValue,
              atRiskDpdThreshold: defaultProduct.atRiskDpdThreshold,
            )
          : defaultProduct;

      final mob = (row.monthsOnBooks ?? 0).clamp(0, row.tenureInstallments);
      final disbursedOn = mob > 0
          ? DateTime(now.year, now.month - mob, now.day.clamp(1, 28))
          : now;

      final createdLoan = await portfolio.originateNewLoan(
        borrower: borrower,
        product: effectiveProduct,
        principalSanctioned: row.amount,
        tenureInstallments: row.tenureInstallments,
        collectedByUid: importedByUid,
        customLoanId: row.loanNo.isNotEmpty ? row.loanNo : null,
        customApplicationNo:
            row.applicationNo.isNotEmpty ? row.applicationNo : null,
        disbursementDate: disbursedOn,
        skipRefresh: true,
      );

      // Settle historical MOB installments + preserve imported DPD & POS in a single atomic update
      final scheduleRows = portfolio.scheduleForLoan(
        createdLoan.loanId,
        version: createdLoan.scheduleVersion,
      );
      final updatedSchedule = <InstallmentModel>[];
      var paidPrincipal = 0.0;
      var paidInterest = 0.0;

      for (var i = 0; i < mob && i < scheduleRows.length; i++) {
        final inst = scheduleRows[i];
        paidPrincipal += inst.principalDue;
        paidInterest += inst.interestDue;
        updatedSchedule.add(
          inst.copyWith(
            principalPaid: inst.principalDue,
            interestPaid: inst.interestDue,
            status: InstallmentStatus.paid,
          ),
        );
      }

      final importedDpd = row.dpd ?? 0;
      final importedPos = row.principalOutstandingOverride;
      final remainingPrincipal = (importedPos != null && importedPos > 0)
          ? importedPos
          : IndianFormatters.roundPaise(
              (createdLoan.principalSanctioned - paidPrincipal)
                  .clamp(0.0, createdLoan.principalSanctioned),
            );
      final remainingInterest = IndianFormatters.roundPaise(
        (createdLoan.interestOutstanding - paidInterest)
            .clamp(0.0, createdLoan.interestOutstanding),
      );

      if (mob > 0 || importedDpd > 0 || (importedPos != null && importedPos > 0)) {
        final updatedLoan = createdLoan.copyWith(
          principalOutstanding: remainingPrincipal,
          interestOutstanding: remainingInterest,
          dpd: importedDpd > 0 ? importedDpd : 0,
          agingBucket: importedDpd > 0
              ? AgingBucket.fromDpd(importedDpd)
              : AgingBucket.current,
        );
        await portfolio.applyBatchImportState(
          updatedLoan: updatedLoan,
          updatedInstallments: updatedSchedule,
          skipRefresh: true,
        );
      }

      imported++;
    }

    if (imported > 0) {
      await portfolio.refresh();
    }

    return imported;
  }

  static List<String> _splitCsvLine(String line) {
    final result = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (ch == ',' && !inQuotes) {
        result.add(buf.toString().trim());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    result.add(buf.toString().trim());
    return result;
  }

  static String _maskGovernmentId(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 4) {
      return 'XXXX-XXXX-${digits.substring(digits.length - 4)}';
    }
    return '';
  }

  static String _digitsOnly(String raw) =>
      raw.replaceAll(RegExp(r'[^0-9]'), '');

  static String _signedDigits(String raw) =>
      raw.replaceAll(RegExp(r'[^0-9-]'), '');

  static String _cellText(Data? cell) {
    final val = cell?.value;
    if (val == null) return '';
    return val.toString().trim();
  }

  static String _safeStr(List<String> row, int idx) {
    if (idx < 0 || idx >= row.length) return '';
    return row[idx].trim();
  }

  static double? _parseDouble(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^0-9.\-]'), '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }
}







