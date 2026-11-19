import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engines/geo_filter_engine.dart';
import '../models/borrower_model.dart';
import '../models/loan_model.dart';
import '../models/transaction_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_loan_service.dart';
import '../services/location_service.dart';
import '../utils/indian_formatters.dart';
import '../screens/loans/loan_detail_screen.dart';
import 'ptp_log_bottom_sheet.dart';

/// Anchors on the currently attended customer's geolocation and surfaces all nearby
/// pending/overdue accounts within an officer-adjustable 2 km – 100 km terrain radius.
class CustomerNearbyRadarSheet extends StatefulWidget {
  const CustomerNearbyRadarSheet({
    super.key,
    required this.anchorBorrower,
    required this.anchorLoan,
    this.initialRadiusKm = 5.0,
    this.agentIdFilter,
  });

  final BorrowerModel anchorBorrower;
  final LoanModel anchorLoan;
  final double initialRadiusKm;
  final String? agentIdFilter;

  static Future<void> show(
    BuildContext context, {
    required BorrowerModel anchorBorrower,
    required LoanModel anchorLoan,
    double initialRadiusKm = 5.0,
    String? agentIdFilter,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => CustomerNearbyRadarSheet(
        anchorBorrower: anchorBorrower,
        anchorLoan: anchorLoan,
        initialRadiusKm: initialRadiusKm,
        agentIdFilter: agentIdFilter,
      ),
    );
  }

  @override
  State<CustomerNearbyRadarSheet> createState() =>
      _CustomerNearbyRadarSheetState();
}

class _CustomerNearbyRadarSheetState extends State<CustomerNearbyRadarSheet> {
  late double _radiusKm;
  bool _overdueOnly = false;
  bool _allZoneAccounts = false;

  static const List<({double km, String tag})> _terrainPresets = [
    (km: 2, tag: '2 km Dense'),
    (km: 5, tag: '5 km City'),
    (km: 15, tag: '15 km Town'),
    (km: 50, tag: '50 km District'),
    (km: 100, tag: '100 km Highway'),
  ];

  @override
  void initState() {
    super.initState();
    _radiusKm = widget.initialRadiusKm.clamp(2.0, 100.0);
  }

  Future<void> _recordQuickReceipt(
    BuildContext context,
    LoanPortfolioProvider portfolio,
    LoanModel loan,
    String uid,
  ) async {
    final amountCtrl = TextEditingController(
      text: loan.emiAmount.toStringAsFixed(0),
    );
    final refCtrl = TextEditingController();
    var mode = PaymentMode.upi;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: Text('Quick Receipt • ${loan.loanId}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Collected Amount (₹)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<PaymentMode>(
                value: mode,
                decoration: const InputDecoration(
                  labelText: 'Payment Mode',
                  border: OutlineInputBorder(),
                ),
                items: PaymentMode.values
                    .where((m) => m != PaymentMode.systemAuto)
                    .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setModalState(() => mode = v);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: refCtrl,
                decoration: const InputDecoration(
                  labelText: 'UTR / Receipt Reference',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final amt = double.tryParse(amountCtrl.text) ?? 0;
                if (amt <= 0) return;
                final loc = await LocationService.getCurrentLocation();
                await portfolio.recordPayment(
                  loanId: loan.loanId,
                  amount: amt,
                  paymentMode: mode,
                  referenceNo: refCtrl.text,
                  collectedByUid: uid,
                  geoLat: loc.latitude,
                  geoLng: loc.longitude,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Receipt of ${IndianFormatters.formatInr(amt)} posted with GPS stamp.',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Save Receipt'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final portfolio = context.watch<LoanPortfolioProvider>();
    final auth = context.watch<AuthService>();

    final effectiveAgentFilter =
        _allZoneAccounts ? null : widget.agentIdFilter;

    final nearbyPins = GeoFilterEngine.filterPins(
      borrowers: portfolio.borrowers,
      loans: portfolio.loans,
      logs: portfolio.collectionLogs,
      originLat: widget.anchorBorrower.latitude,
      originLng: widget.anchorBorrower.longitude,
      maxRadiusKm: _radiusKm,
      agentIdFilter: effectiveAgentFilter,
      optimizeRouteOrder: false, // Sort strictly closest-first from attended customer
    ).where((p) {
      if (p.primaryLoan.loanId == widget.anchorLoan.loanId) return false;
      if (_overdueOnly && p.primaryLoan.dpd <= 0 && !p.hasPtpDueToday) {
        return false;
      }
      return true;
    }).toList();

    final totalNearbyPending = nearbyPins.fold<double>(
      0.0,
      (sum, p) => sum + p.primaryLoan.totalOutstanding,
    );

    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.radar, color: Colors.indigo),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nearby Collections Around ${widget.anchorBorrower.fullName}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${widget.anchorBorrower.addressText} • ${nearbyPins.length} accounts (${IndianFormatters.formatInrCompact(totalNearbyPending)}) within ${_radiusKm.round()} km',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(
              children: [
                Text(
                  'Radius: ${_radiusKm.round()} km',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.indigo,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: _radiusKm,
                    min: 2,
                    max: 100,
                    divisions: 49,
                    label: '${_radiusKm.round()} km',
                    onChanged: (v) => setState(() => _radiusKm = v),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                for (final preset in _terrainPresets) ...[
                  ChoiceChip(
                    label: Text(preset.tag, style: const TextStyle(fontSize: 11)),
                    selected: (_radiusKm - preset.km).abs() < 0.5,
                    onSelected: (_) => setState(() => _radiusKm = preset.km),
                  ),
                  const SizedBox(width: 6),
                ],
                FilterChip(
                  label: const Text('Overdue / PTP Only',
                      style: TextStyle(fontSize: 11)),
                  selected: _overdueOnly,
                  onSelected: (v) => setState(() => _overdueOnly = v),
                ),
                if (widget.agentIdFilter != null) ...[
                  const SizedBox(width: 6),
                  FilterChip(
                    label: const Text('Show All Zone Staff',
                        style: TextStyle(fontSize: 11)),
                    selected: _allZoneAccounts,
                    onSelected: (v) => setState(() => _allZoneAccounts = v),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 12),
          Expanded(
            child: nearbyPins.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No other pending borrower accounts within ${_radiusKm.round()} km of ${widget.anchorBorrower.fullName}.\n'
                        'Slide radius up (up to 100 km) for wider district/highway coverage.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                    itemCount: nearbyPins.length,
                    itemBuilder: (context, idx) {
                      final pin = nearbyPins[idx];
                      final b = pin.borrower;
                      final loan = pin.primaryLoan;
                      final distLabel = pin.distanceKm < 1.0
                          ? '${(pin.distanceKm * 1000).round()} m away'
                          : '${pin.distanceKm.toStringAsFixed(1)} km away';
                      final statusColor = loan.dpd >= 31 || pin.hasBrokenPtp
                          ? Colors.red.shade700
                          : loan.dpd > 0 || pin.hasPtpDueToday
                              ? Colors.amber.shade800
                              : Colors.green.shade700;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: statusColor.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.indigo.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      distLabel,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                        color: Colors.indigo.shade800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      b.fullName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    loan.dpd > 0
                                        ? '${loan.dpd} DPD'
                                        : 'CURRENT',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: statusColor,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${loan.loanId} • ${b.addressText} • ${b.mobilePrimary}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 12,
                                children: [
                                  Text(
                                    'Pending: ${IndianFormatters.formatInr(loan.totalOutstanding, showDecimals: false)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    'EMI: ${IndianFormatters.formatInr(loan.emiAmount, showDecimals: false)}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                              const Divider(height: 14),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  FilledButton.tonalIcon(
                                    onPressed: () =>
                                        LocationService.launchGoogleMapsNavigation(
                                      b.latitude,
                                      b.longitude,
                                    ),
                                    icon: const Icon(Icons.navigation, size: 15),
                                    label: const Text('Navigate'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        LocationService.launchPhoneCall(
                                      b.mobilePrimary,
                                    ),
                                    icon: const Icon(Icons.call, size: 15),
                                    label: const Text('Call'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => PtpLogBottomSheet.show(
                                      context,
                                      loan: loan,
                                      borrower: b,
                                      agentId: auth.currentUser?.uid ??
                                          loan.assignedAgentId,
                                      onSave: portfolio.logCollectionActivity,
                                    ),
                                    icon: const Icon(Icons.event_note, size: 15),
                                    label: const Text('Log PTP'),
                                  ),
                                  FilledButton.icon(
                                    onPressed: () => _recordQuickReceipt(
                                      context,
                                      portfolio,
                                      loan,
                                      auth.currentUser?.uid ??
                                          loan.assignedAgentId,
                                    ),
                                    icon: const Icon(Icons.currency_rupee,
                                        size: 15),
                                    label: const Text('Collect'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => LoanDetailScreen(
                                          loanId: loan.loanId,
                                        ),
                                      ),
                                    ),
                                    child: const Text('360° File'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
