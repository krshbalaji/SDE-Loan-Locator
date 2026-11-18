import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../engines/geo_filter_engine.dart';
import '../../models/loan_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_loan_service.dart';
import '../../services/location_service.dart';
import '../../widgets/borrower_map_card.dart';
import '../../widgets/ptp_log_bottom_sheet.dart';
import '../loans/loan_detail_screen.dart';

/// Upgraded Geo-Map & Field Route Locator:
/// Green/Amber/Red health pins, 50 km Haversine radius, Agent / Bucket / PTP Due Today filters,
/// greedy route ordering, and on-site GPS check-in verification.
class FieldLocatorMapScreen extends StatefulWidget {
  const FieldLocatorMapScreen({super.key, this.lockedAgentId});

  final String? lockedAgentId;

  @override
  State<FieldLocatorMapScreen> createState() => _FieldLocatorMapScreenState();
}

class _FieldLocatorMapScreenState extends State<FieldLocatorMapScreen> {
  double _originLat = LocationService.defaultLat;
  double _originLng = LocationService.defaultLng;
  double _radiusKm = 50.0;
  String? _agentFilter;
  AgingBucket? _bucketFilter;
  bool _ptpDueTodayOnly = false;
  bool _optimizeRoute = true;
  bool _showMapView = !kIsWeb; // Route List works reliably on Web/Windows even without Maps API key
  String _searchQuery = '';
  String? _selectedLoanId;

  @override
  void initState() {
    super.initState();
    _agentFilter = widget.lockedAgentId;
    _refreshLocation();
  }

  Future<void> _refreshLocation() async {
    final loc = await LocationService.getCurrentLocation();
    if (!mounted) return;
    setState(() {
      _originLat = loc.latitude;
      _originLng = loc.longitude;
    });
  }

  double _markerHue(PinHealth health) {
    switch (health) {
      case PinHealth.green:
        return BitmapDescriptor.hueGreen;
      case PinHealth.amber:
        return BitmapDescriptor.hueOrange;
      case PinHealth.red:
        return BitmapDescriptor.hueRed;
    }
  }

  Future<void> _performGeoCheckIn(
    LoanPortfolioProvider portfolio,
    GeoBorrowerPin pin,
  ) async {
    final loc = await LocationService.getCurrentLocation();
    final check = GeoFilterEngine.verifyCheckInProximity(
      agentLat: loc.latitude,
      agentLng: loc.longitude,
      borrowerLat: pin.borrower.latitude,
      borrowerLng: pin.borrower.longitude,
    );

    await portfolio.verifyBorrowerGeoPin(
      borrowerId: pin.borrower.borrowerId,
      latitude: pin.borrower.latitude,
      longitude: pin.borrower.longitude,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          check.isVerified
              ? 'On-site check-in verified (${check.distanceMeters.toStringAsFixed(0)}m from pin)!'
              : 'Pin stamped (${(check.distanceMeters / 1000).toStringAsFixed(2)} km from current GPS).',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final portfolio = context.watch<LoanPortfolioProvider>();
    final auth = context.watch<AuthService>();
    final activeAgentFilter = widget.lockedAgentId ?? _agentFilter;

    final pins = GeoFilterEngine.filterPins(
      borrowers: portfolio.borrowers,
      loans: portfolio.loans,
      logs: portfolio.collectionLogs,
      originLat: _originLat,
      originLng: _originLng,
      maxRadiusKm: _radiusKm,
      agentIdFilter: activeAgentFilter,
      agingBucketFilter: _bucketFilter,
      ptpDueTodayOnly: _ptpDueTodayOnly,
      searchQuery: _searchQuery,
      optimizeRouteOrder: _optimizeRoute,
    );

    GeoBorrowerPin? selectedPin;
    if (_selectedLoanId != null) {
      for (final p in pins) {
        if (p.primaryLoan.loanId == _selectedLoanId) {
          selectedPin = p;
          break;
        }
      }
    }
    selectedPin ??= pins.isNotEmpty ? pins.first : null;

    final markers = pins.map((pin) {
      return Marker(
        markerId: MarkerId(pin.primaryLoan.loanId),
        position: LatLng(pin.borrower.latitude, pin.borrower.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(_markerHue(pin.health)),
        infoWindow: InfoWindow(
          title: pin.borrower.fullName,
          snippet: '${pin.primaryLoan.loanId} • ${pin.primaryLoan.dpd} DPD',
        ),
        onTap: () => setState(() => _selectedLoanId = pin.primaryLoan.loanId),
      );
    }).toSet();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search borrower, area, or loan ID...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.route, size: 16),
                    label: Text('Route'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.map, size: 16),
                    label: Text('Map'),
                  ),
                ],
                selected: {_showMapView},
                onSelectionChanged: (s) =>
                    setState(() => _showMapView = s.first),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              ActionChip(
                avatar: const Icon(Icons.radar, size: 16),
                label: Text('Radius: ${_radiusKm.round()} km'),
                onPressed: () {
                  setState(() {
                    _radiusKm = _radiusKm >= 100
                        ? 10
                        : _radiusKm == 50
                            ? 100
                            : 50;
                  });
                },
              ),
              const SizedBox(width: 6),
              FilterChip(
                label: const Text('PTP Due Today'),
                selected: _ptpDueTodayOnly,
                onSelected: (v) => setState(() => _ptpDueTodayOnly = v),
              ),
              const SizedBox(width: 6),
              FilterChip(
                label: const Text('Auto-Route'),
                selected: _optimizeRoute,
                onSelected: (v) => setState(() => _optimizeRoute = v),
              ),
              const SizedBox(width: 6),
              if (widget.lockedAgentId == null) ...[
                DropdownButton<String?>(
                  value: _agentFilter,
                  hint: const Text('All Agents'),
                  underline: const SizedBox.shrink(),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All Agents'),
                    ),
                    for (final entry in auth.knownAgentNames.entries)
                      DropdownMenuItem<String?>(
                        value: entry.key,
                        child: Text(entry.value.split(' (').first),
                      ),
                  ],
                  onChanged: (v) => setState(() => _agentFilter = v),
                ),
                const SizedBox(width: 8),
              ],
              for (final bucket in AgingBucket.values) ...[
                FilterChip(
                  label: Text(bucket.label),
                  selected: _bucketFilter == bucket,
                  onSelected: (sel) =>
                      setState(() => _bucketFilter = sel ? bucket : null),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          child: Row(
            children: [
              Text(
                '${pins.length} borrower pin(s) within ${_radiusKm.round()} km',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const Spacer(),
              _legendDot(Colors.green.shade700, 'Current'),
              const SizedBox(width: 8),
              _legendDot(Colors.amber.shade800, '1–30 / PTP'),
              const SizedBox(width: 8),
              _legendDot(Colors.red.shade700, '31+ / Broken'),
            ],
          ),
        ),
        Expanded(
          child: pins.isEmpty
              ? const Center(
                  child: Text('No borrower pins match the active geo-filters.'),
                )
              : _showMapView
                  ? Column(
                      children: [
                        Expanded(
                          child: GoogleMap(
                            initialCameraPosition: CameraPosition(
                              target: LatLng(_originLat, _originLng),
                              zoom: 12.5,
                            ),
                            markers: markers,
                            myLocationEnabled: false,
                          ),
                        ),
                        if (selectedPin != null)
                          BorrowerMapCard(
                            pin: selectedPin,
                            onOpenLoanDetail: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => LoanDetailScreen(
                                  loanId: selectedPin!.primaryLoan.loanId,
                                ),
                              ),
                            ),
                            onLogPtp: () => PtpLogBottomSheet.show(
                              context,
                              loan: selectedPin!.primaryLoan,
                              borrower: selectedPin.borrower,
                              agentId: auth.currentUser?.uid ??
                                  selectedPin.primaryLoan.assignedAgentId,
                              onSave: portfolio.logCollectionActivity,
                            ),
                            onCheckIn: () =>
                                _performGeoCheckIn(portfolio, selectedPin!),
                          ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: pins.length,
                      itemBuilder: (context, idx) {
                        final pin = pins[idx];
                        return BorrowerMapCard(
                          pin: pin,
                          routeStopNumber: _optimizeRoute ? idx + 1 : null,
                          onOpenLoanDetail: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => LoanDetailScreen(
                                loanId: pin.primaryLoan.loanId,
                              ),
                            ),
                          ),
                          onLogPtp: () => PtpLogBottomSheet.show(
                            context,
                            loan: pin.primaryLoan,
                            borrower: pin.borrower,
                            agentId: auth.currentUser?.uid ??
                                pin.primaryLoan.assignedAgentId,
                            onSave: portfolio.logCollectionActivity,
                          ),
                          onCheckIn: () => _performGeoCheckIn(portfolio, pin),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
