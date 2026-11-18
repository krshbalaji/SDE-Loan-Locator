import 'package:flutter/material.dart';

import '../engines/geo_filter_engine.dart';
import '../services/location_service.dart';
import '../utils/indian_formatters.dart';

/// Rich summary card for a geo-located borrower pin on the Field Map or Route List.
class BorrowerMapCard extends StatelessWidget {
  const BorrowerMapCard({
    super.key,
    required this.pin,
    required this.onOpenLoanDetail,
    required this.onLogPtp,
    required this.onCheckIn,
    this.routeStopNumber,
  });

  final GeoBorrowerPin pin;
  final VoidCallback onOpenLoanDetail;
  final VoidCallback onLogPtp;
  final VoidCallback onCheckIn;
  final int? routeStopNumber;

  Color _healthColor() {
    switch (pin.health) {
      case PinHealth.green:
        return Colors.green.shade700;
      case PinHealth.amber:
        return Colors.amber.shade800;
      case PinHealth.red:
        return Colors.red.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    final borrower = pin.borrower;
    final loan = pin.primaryLoan;
    final color = _healthColor();

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.4), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (routeStopNumber != null)
                  Container(
                    width: 28,
                    height: 28,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$routeStopNumber',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        borrower.fullName,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${loan.loanId} • ${borrower.addressText}',
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Chip(
                  backgroundColor: color.withValues(alpha: 0.14),
                  side: BorderSide.none,
                  label: Text(
                    loan.dpd > 0 ? '${loan.dpd} DPD' : 'CURRENT',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _metric(
                  'Outstanding',
                  IndianFormatters.formatInr(loan.totalOutstanding,
                      showDecimals: false),
                ),
                _metric(
                  'EMI',
                  IndianFormatters.formatInr(loan.emiAmount,
                      showDecimals: false),
                ),
                _metric(
                  'Distance',
                  '${pin.distanceKm.toStringAsFixed(1)} km',
                ),
                if (pin.hasBrokenPtp)
                  _badge('BROKEN PTP', Colors.red.shade700),
                if (pin.hasPtpDueToday)
                  _badge('PTP DUE TODAY', Colors.amber.shade800),
                if (borrower.geoVerified)
                  _badge('GEO VERIFIED', Colors.teal.shade700),
              ],
            ),
            const Divider(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FilledButton.icon(
                  onPressed: () => LocationService.launchGoogleMapsNavigation(
                    borrower.latitude,
                    borrower.longitude,
                  ),
                  icon: const Icon(Icons.navigation, size: 16),
                  label: const Text('Navigate'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      LocationService.launchPhoneCall(borrower.mobilePrimary),
                  icon: const Icon(Icons.call, size: 16),
                  label: const Text('Call'),
                ),
                OutlinedButton.icon(
                  onPressed: () => LocationService.launchWhatsAppReminder(
                    mobile: borrower.mobilePrimary,
                    message:
                        'Namaste ${borrower.fullName}, reminder from Saro Devi Enterprises regarding Loan ${loan.loanId}. '
                        'EMI ${IndianFormatters.formatInr(loan.emiAmount, showDecimals: false)} '
                        '(Outstanding: ${IndianFormatters.formatInr(loan.totalOutstanding, showDecimals: false)}).',
                  ),
                  icon: const Icon(Icons.chat, size: 16),
                  label: const Text('WhatsApp'),
                ),
                OutlinedButton.icon(
                  onPressed: onCheckIn,
                  icon: const Icon(Icons.my_location, size: 16),
                  label: const Text('Check-In'),
                ),
                OutlinedButton.icon(
                  onPressed: onLogPtp,
                  icon: const Icon(Icons.event_note, size: 16),
                  label: const Text('Log PTP'),
                ),
                TextButton.icon(
                  onPressed: onOpenLoanDetail,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('360° File'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
