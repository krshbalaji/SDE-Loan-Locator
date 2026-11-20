import 'dart:math';

import '../models/borrower_model.dart';
import '../models/collection_log_model.dart';
import '../models/loan_model.dart';

enum PinHealth {
  green('CURRENT', 'Current'),
  amber('ATTENTION', 'DPD 1â€“30 / PTP Due'),
  red('CRITICAL', 'DPD 31+ / Broken PTP');

  const PinHealth(this.code, this.label);
  final String code;
  final String label;
}

class GeoBorrowerPin {
  const GeoBorrowerPin({
    required this.borrower,
    required this.primaryLoan,
    required this.health,
    required this.distanceKm,
    required this.hasPtpDueToday,
    required this.hasBrokenPtp,
  });

  final BorrowerModel borrower;
  final LoanModel primaryLoan;
  final PinHealth health;
  final double distanceKm;
  final bool hasPtpDueToday;
  final bool hasBrokenPtp;
}

/// Geo-Spatial Engine: LatLong parsing, Geohash encoding, Haversine filtering & route ordering.
class GeoFilterEngine {
  GeoFilterEngine._();

  static const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

  /// Safely parses strings like `"9.9252, 78.1198"` or `"9.9252Â° N, 78.1198Â° E"`.
  static ({double lat, double lng})? parseLatLong(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final parts = trimmed.split(',');
    if (parts.length != 2) return null;

    final latClean = parts[0].replaceAll(RegExp(r'[^0-9.\-]'), '');
    final lngClean = parts[1].replaceAll(RegExp(r'[^0-9.\-]'), '');
    var lat = double.tryParse(latClean);
    var lng = double.tryParse(lngClean);
    if (lat == null || lng == null) return null;

    if (parts[0].toUpperCase().contains('S') && lat > 0) lat = -lat;
    if (parts[1].toUpperCase().contains('W') && lng > 0) lng = -lng;

    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return (lat: lat, lng: lng);
  }

  /// Standard base-32 Geohash encoder for Firestore 50 km radius indexing.
  static String encodeGeohash(
    double latitude,
    double longitude, {
    int precision = 7,
  }) {
    var minLat = -90.0;
    var maxLat = 90.0;
    var minLng = -180.0;
    var maxLng = 180.0;
    var isEven = true;
    var bit = 0;
    var ch = 0;
    final buffer = StringBuffer();

    while (buffer.length < precision) {
      if (isEven) {
        final mid = (minLng + maxLng) / 2;
        if (longitude >= mid) {
          ch |= 1 << (4 - bit);
          minLng = mid;
        } else {
          maxLng = mid;
        }
      } else {
        final mid = (minLat + maxLat) / 2;
        if (latitude >= mid) {
          ch |= 1 << (4 - bit);
          minLat = mid;
        } else {
          maxLat = mid;
        }
      }
      isEven = !isEven;
      if (bit < 4) {
        bit++;
      } else {
        buffer.write(_base32[ch]);
        bit = 0;
        ch = 0;
      }
    }
    return buffer.toString();
  }

  /// Haversine great-circle distance in kilometers.
  static double haversineDistanceKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const p = pi / 180.0;
    final a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lng2 - lng1) * p)) / 2;
    return 12742.0 * asin(sqrt(a.clamp(0.0, 1.0)));
  }

  /// Checks whether agent field check-in coordinates are within [maxMeters] of borrower pin.
  static ({bool isVerified, double distanceMeters}) verifyCheckInProximity({
    required double agentLat,
    required double agentLng,
    required double borrowerLat,
    required double borrowerLng,
    double maxMeters = 250.0,
  }) {
    final meters =
        haversineDistanceKm(agentLat, agentLng, borrowerLat, borrowerLng) *
            1000.0;
    return (isVerified: meters <= maxMeters, distanceMeters: meters);
  }

  static PinHealth evaluatePinHealth({
    required LoanModel loan,
    required bool hasPtpDueToday,
    required bool hasBrokenPtp,
  }) {
    if (loan.dpd >= 31 || hasBrokenPtp) return PinHealth.red;
    if ((loan.dpd >= 1 && loan.dpd <= 30) || hasPtpDueToday) {
      return PinHealth.amber;
    }
    return PinHealth.green;
  }

  /// Filters borrower-loan pins by radius, agent, aging bucket, PTP due today, and search query,
  /// optionally ordering them via nearest-neighbor greedy route traversal.
  static List<GeoBorrowerPin> filterPins({
    required List<BorrowerModel> borrowers,
    required List<LoanModel> loans,
    required List<CollectionLogModel> logs,
    required double originLat,
    required double originLng,
    double maxRadiusKm = 50.0,
    String? agentIdFilter,
    AgingBucket? agingBucketFilter,
    bool ptpDueTodayOnly = false,
    String searchQuery = '',
    bool optimizeRouteOrder = true,
    DateTime? asOfDate,
  }) {
    final now = asOfDate ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final query = searchQuery.trim().toLowerCase();

    final borrowerMap = {for (final b in borrowers) b.borrowerId: b};
    final pins = <GeoBorrowerPin>[];

    for (final loan in loans.where((l) => l.isPortfolioActive)) {
      final borrower = borrowerMap[loan.borrowerId];
      if (borrower == null || !borrower.hasValidCoordinates) continue;

      if (agentIdFilter != null &&
          agentIdFilter.isNotEmpty &&
          loan.assignedAgentId != agentIdFilter) {
        continue;
      }

      if (agingBucketFilter != null && loan.agingBucket != agingBucketFilter) {
        continue;
      }

      if (query.isNotEmpty) {
        final haystack =
            '${borrower.fullName} ${borrower.addressText} ${borrower.mobilePrimary} ${loan.loanId} ${loan.applicationNo}'
                .toLowerCase();
        if (!haystack.contains(query)) continue;
      }

      final loanLogs = logs.where((l) => l.loanId == loan.loanId).toList();
      final hasBrokenPtp = loanLogs.any((l) => l.ptpStatus == PtpStatus.broken);
      final hasPtpDueToday = loanLogs.any((l) {
        if (l.ptpStatus != PtpStatus.open || l.ptpDate == null) return false;
        final d = DateTime(l.ptpDate!.year, l.ptpDate!.month, l.ptpDate!.day);
        return d.isAtSameMomentAs(today);
      });

      if (ptpDueTodayOnly && !hasPtpDueToday) continue;

      final distKm = haversineDistanceKm(
        originLat,
        originLng,
        borrower.latitude,
        borrower.longitude,
      );
      if (distKm > maxRadiusKm) continue;

      pins.add(
        GeoBorrowerPin(
          borrower: borrower,
          primaryLoan: loan,
          health: evaluatePinHealth(
            loan: loan,
            hasPtpDueToday: hasPtpDueToday,
            hasBrokenPtp: hasBrokenPtp,
          ),
          distanceKm: distKm,
          hasPtpDueToday: hasPtpDueToday,
          hasBrokenPtp: hasBrokenPtp,
        ),
      );
    }

    if (!optimizeRouteOrder || pins.length <= 2) {
      pins.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
      return pins;
    }

    // Nearest-neighbor greedy route starting from originLat/originLng
    final remaining = List<GeoBorrowerPin>.from(pins);
    final ordered = <GeoBorrowerPin>[];
    var curLat = originLat;
    var curLng = originLng;

    while (remaining.isNotEmpty) {
      var bestIdx = 0;
      var bestDist = double.infinity;
      for (var i = 0; i < remaining.length; i++) {
        final d = haversineDistanceKm(
          curLat,
          curLng,
          remaining[i].borrower.latitude,
          remaining[i].borrower.longitude,
        );
        if (d < bestDist) {
          bestDist = d;
          bestIdx = i;
        }
      }
      final next = remaining.removeAt(bestIdx);
      ordered.add(next);
      curLat = next.borrower.latitude;
      curLng = next.borrower.longitude;
    }

    return ordered;
  }
}

