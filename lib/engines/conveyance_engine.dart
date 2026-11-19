import 'dart:math';

import '../models/borrower_model.dart';
import '../models/collection_log_model.dart';
import '../models/transaction_model.dart';
import '../utils/indian_formatters.dart';
import 'geo_filter_engine.dart';

class FieldStopEvent {
  const FieldStopEvent({
    required this.timestamp,
    required this.loanId,
    required this.borrowerName,
    required this.activityType,
    required this.latitude,
    required this.longitude,
    required this.isGeoVerified,
    required this.legDistanceKm,
    required this.amountCollected,
  });

  final DateTime timestamp;
  final String loanId;
  final String borrowerName;
  final String activityType; // 'Field Visit' | 'Payment Receipt'
  final double latitude;
  final double longitude;
  final bool isGeoVerified;
  final double legDistanceKm;
  final double amountCollected;
}

class AgentConveyanceSummary {
  const AgentConveyanceSummary({
    required this.agentId,
    required this.agentName,
    required this.activeFieldDays,
    required this.totalStopsCount,
    required this.verifiedOnSiteStops,
    required this.verifiedRoadKm,
    required this.reimbursementInr,
    required this.totalCollectedInr,
    required this.collectionPerKmInr,
    required this.recentStops,
  });

  final String agentId;
  final String agentName;
  final int activeFieldDays;
  final int totalStopsCount;
  final int verifiedOnSiteStops;
  final double verifiedRoadKm;
  final double reimbursementInr;
  final double totalCollectedInr;
  final double collectionPerKmInr;
  final List<FieldStopEvent> recentStops;
}

/// Computes automated daily/monthly field travel distance and Local Conveyance (TA/DA)
/// directly from geo-stamped field visits & payment receipts—zero manual logs needed.
class ConveyanceEngine {
  ConveyanceEngine._();

  /// Realistic Indian road-to-Haversine multiplier (accounts for turns/lanes vs straight line).
  static const double defaultRoadFactor = 1.25;

  /// Default two-wheeler field reimbursement rate in INR per verified km.
  static const double defaultRatePerKmInr = 4.50;

  static List<AgentConveyanceSummary> computePeriodConveyance({
    required List<CollectionLogModel> logs,
    required List<TransactionModel> transactions,
    required List<BorrowerModel> borrowers,
    required Map<String, String> agentNames,
    required DateTime fromDate,
    required DateTime toDate,
    double ratePerKmInr = defaultRatePerKmInr,
    double roadFactor = defaultRoadFactor,
  }) {
    final borrowerMap = {for (final b in borrowers) b.borrowerId: b};
    final start = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final end = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59);

    final rawByAgent = <String, List<_RawGeoEvent>>{};

    for (final log in logs) {
      if (log.visitLat == null || log.visitLng == null) continue;
      if (log.createdAt.isBefore(start) || log.createdAt.isAfter(end)) continue;
      final b = borrowerMap[log.borrowerId];
      final verified = b != null &&
          b.hasValidCoordinates &&
          GeoFilterEngine.verifyCheckInProximity(
            agentLat: log.visitLat!,
            agentLng: log.visitLng!,
            borrowerLat: b.latitude,
            borrowerLng: b.longitude,
          ).isVerified;

      rawByAgent.putIfAbsent(log.agentId, () => []).add(
            _RawGeoEvent(
              timestamp: log.createdAt,
              loanId: log.loanId,
              borrowerName: b?.fullName ?? log.borrowerId,
              activityType: log.actionType.label,
              lat: log.visitLat!,
              lng: log.visitLng!,
              isGeoVerified: verified,
              amountCollected: 0.0,
            ),
          );
    }

    for (final txn in transactions) {
      if (!txn.isCreditToLoan) continue;
      if (txn.createdAt.isBefore(start) || txn.createdAt.isAfter(end)) continue;
      final b = borrowerMap[txn.borrowerId];
      final hasGps = txn.geoLat != null && txn.geoLng != null;
      final verified = hasGps &&
          b != null &&
          b.hasValidCoordinates &&
          GeoFilterEngine.verifyCheckInProximity(
            agentLat: txn.geoLat!,
            agentLng: txn.geoLng!,
            borrowerLat: b.latitude,
            borrowerLng: b.longitude,
          ).isVerified;

      rawByAgent.putIfAbsent(txn.collectedByUid, () => []).add(
            _RawGeoEvent(
              timestamp: txn.createdAt,
              loanId: txn.loanId,
              borrowerName: b?.fullName ?? txn.borrowerId,
              activityType: 'Receipt (${txn.paymentMode.label})',
              lat: txn.geoLat ?? 0.0,
              lng: txn.geoLng ?? 0.0,
              isGeoVerified: verified,
              amountCollected: txn.totalAmount,
            ),
          );
    }

    final allAgentIds = <String>{...agentNames.keys, ...rawByAgent.keys}
      ..removeWhere((id) => id.isEmpty);

    final summaries = <AgentConveyanceSummary>[];

    for (final agentId in allAgentIds) {
      final events = List<_RawGeoEvent>.from(rawByAgent[agentId] ?? const []);
      events.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      final activeDays = <String>{};
      var verifiedStops = 0;
      var totalRoadKm = 0.0;
      var totalCollected = 0.0;
      final builtStops = <FieldStopEvent>[];

      String? currentDayKey;
      double? prevVerifiedLat;
      double? prevVerifiedLng;

      for (final ev in events) {
        totalCollected += ev.amountCollected;
        final dayKey =
            '${ev.timestamp.year}-${ev.timestamp.month.toString().padLeft(2, '0')}-${ev.timestamp.day.toString().padLeft(2, '0')}';

        if (dayKey != currentDayKey) {
          currentDayKey = dayKey;
          prevVerifiedLat = null;
          prevVerifiedLng = null;
        }

        var legKm = 0.0;
        if (ev.isGeoVerified) {
          activeDays.add(dayKey);
          verifiedStops++;
          if (prevVerifiedLat != null && prevVerifiedLng != null) {
            final straightKm = GeoFilterEngine.haversineDistanceKm(
              prevVerifiedLat,
              prevVerifiedLng,
              ev.lat,
              ev.lng,
            );
            // Ignore duplicate pings at the exact same doorstep (< 80m)
            if (straightKm > 0.08) {
              legKm = IndianFormatters.roundPaise(straightKm * roadFactor);
              totalRoadKm += legKm;
            }
          }
          prevVerifiedLat = ev.lat;
          prevVerifiedLng = ev.lng;
        }

        builtStops.add(
          FieldStopEvent(
            timestamp: ev.timestamp,
            loanId: ev.loanId,
            borrowerName: ev.borrowerName,
            activityType: ev.activityType,
            latitude: ev.lat,
            longitude: ev.lng,
            isGeoVerified: ev.isGeoVerified,
            legDistanceKm: legKm,
            amountCollected: ev.amountCollected,
          ),
        );
      }

      final roundedKm = IndianFormatters.roundPaise(totalRoadKm);
      final reimbursement =
          IndianFormatters.roundPaise(roundedKm * max(0.0, ratePerKmInr));
      final roundedCollected = IndianFormatters.roundPaise(totalCollected);
      final yieldPerKm = roundedKm > 0
          ? IndianFormatters.roundPaise(roundedCollected / roundedKm)
          : 0.0;

      summaries.add(
        AgentConveyanceSummary(
          agentId: agentId,
          agentName: agentNames[agentId] ?? agentId,
          activeFieldDays: activeDays.length,
          totalStopsCount: events.length,
          verifiedOnSiteStops: verifiedStops,
          verifiedRoadKm: roundedKm,
          reimbursementInr: reimbursement,
          totalCollectedInr: roundedCollected,
          collectionPerKmInr: yieldPerKm,
          recentStops: builtStops.reversed.take(15).toList(),
        ),
      );
    }

    summaries.sort((a, b) => b.verifiedRoadKm.compareTo(a.verifiedRoadKm));
    return summaries;
  }
}

class _RawGeoEvent {
  const _RawGeoEvent({
    required this.timestamp,
    required this.loanId,
    required this.borrowerName,
    required this.activityType,
    required this.lat,
    required this.lng,
    required this.isGeoVerified,
    required this.amountCollected,
  });

  final DateTime timestamp;
  final String loanId;
  final String borrowerName;
  final String activityType;
  final double lat;
  final double lng;
  final bool isGeoVerified;
  final double amountCollected;
}
