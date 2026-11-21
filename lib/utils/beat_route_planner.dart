import 'dart:math';

import '../models/borrower_model.dart';
import '../models/loan_model.dart';

class BeatStop {
  const BeatStop({
    required this.sequence,
    required this.loan,
    required this.borrower,
    required this.legDistanceKm,
    required this.cumulativeDistanceKm,
    required this.estimatedMinutes,
  });

  final int sequence;
  final LoanModel loan;
  final BorrowerModel? borrower;
  final double legDistanceKm;
  final double cumulativeDistanceKm;
  final int estimatedMinutes;
}

class BeatRoutePlan {
  const BeatRoutePlan({
    required this.stops,
    required this.skippedCount,
    required this.totalDistanceKm,
    required this.estimatedTotalMinutes,
  });

  final List<BeatStop> stops;
  final int skippedCount;
  final double totalDistanceKm;
  final int estimatedTotalMinutes;
}

/// Plans an ordered collection beat using Haversine nearest-neighbor routing
/// with a slight priority weight for higher-DPD overdue accounts.
class BeatRoutePlanner {
  BeatRoutePlanner._();

  static const double defaultOriginLat = 9.9252;
  static const double defaultOriginLng = 78.1198;

  static double haversineKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final a = pow(sin(dLat / 2), 2) +
        cos(_degToRad(lat1)) * cos(_degToRad(lat2)) * pow(sin(dLng / 2), 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _degToRad(double deg) => deg * (pi / 180.0);

  static BeatRoutePlan planRoute({
    required List<LoanModel> loans,
    required Map<String, BorrowerModel> borrowerMap,
    double originLat = defaultOriginLat,
    double originLng = defaultOriginLng,
    double avgSpeedKmh = 22.0,
    int stopMinutes = 12,
  }) {
    final candidates = <({LoanModel loan, BorrowerModel borrower, double lat, double lng})>[];
    var skipped = 0;

    for (final loan in loans) {
      final b = borrowerMap[loan.borrowerId];
      final lat = b?.latitude;
      final lng = b?.longitude;
      if (b == null || lat == null || lng == null || (lat == 0 && lng == 0)) {
        skipped++;
        continue;
      }
      candidates.add((loan: loan, borrower: b, lat: lat, lng: lng));
    }

    var curLat = originLat;
    var curLng = originLng;
    var cumulativeKm = 0.0;
    var totalMinutes = 0;
    final remaining = List.of(candidates);
    final stops = <BeatStop>[];
    var seq = 1;

    while (remaining.isNotEmpty) {
      var bestIdx = 0;
      var bestScore = double.infinity;

      for (var i = 0; i < remaining.length; i++) {
        final item = remaining[i];
        final distKm = haversineKm(curLat, curLng, item.lat, item.lng);
        final dpdDiscount = (item.loan.dpd.clamp(0, 180) / 180.0) * 1.25;
        final score = max(0.05, distKm - dpdDiscount);
        if (score < bestScore) {
          bestScore = score;
          bestIdx = i;
        }
      }

      final chosen = remaining.removeAt(bestIdx);
      final legKm = haversineKm(curLat, curLng, chosen.lat, chosen.lng);
      cumulativeKm += legKm;
      final travelMins = ((legKm / avgSpeedKmh) * 60).round();
      totalMinutes += travelMins + stopMinutes;

      stops.add(
        BeatStop(
          sequence: seq++,
          loan: chosen.loan,
          borrower: chosen.borrower,
          legDistanceKm: double.parse(legKm.toStringAsFixed(2)),
          cumulativeDistanceKm: double.parse(cumulativeKm.toStringAsFixed(2)),
          estimatedMinutes: totalMinutes,
        ),
      );

      curLat = chosen.lat;
      curLng = chosen.lng;
    }

    return BeatRoutePlan(
      stops: stops,
      skippedCount: skipped,
      totalDistanceKm: double.parse(cumulativeKm.toStringAsFixed(2)),
      estimatedTotalMinutes: totalMinutes,
    );
  }
}
