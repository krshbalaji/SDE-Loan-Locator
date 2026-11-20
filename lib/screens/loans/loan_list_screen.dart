import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engines/amortization_engine.dart';
import '../../engines/geo_filter_engine.dart';
import '../../models/borrower_model.dart';
import '../../models/loan_model.dart';
import '../../models/loan_product_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_loan_service.dart';
import '../../services/location_service.dart';
import '../../utils/indian_formatters.dart';
import '../../utils/omni_search.dart';
import 'loan_detail_screen.dart';

/// Portfolio loan directory with search, aging filters, and New Loan Origination dialog.
class LoanListScreen extends StatefulWidget {
  const LoanListScreen({super.key, this.agentIdFilter});

  final String? agentIdFilter;

  @override
  State<LoanListScreen> createState() => _LoanListScreenState();
}

class _LoanListScreenState extends State<LoanListScreen> {
  String _search = '';
  AgingBucket? _bucketFilter;

  Future<void> _showOriginateLoanDialog(
    LoanPortfolioProvider portfolio,
    AuthService auth,
  ) async {
    if (portfolio.products.isEmpty) return;

    final nameCtrl = TextEditingController();
    final mobileCtrl = TextEditingController();
    final panCtrl = TextEditingController();
    final aadhaarCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final principalCtrl = TextEditingController(text: '100000');
    final tenureCtrl = TextEditingController(text: '12');

    var selectedProduct = portfolio.products.first;
    double lat = LocationService.defaultLat;
    double lng = LocationService.defaultLng;
    var geoCaptured = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          final principal = double.tryParse(principalCtrl.text) ?? 0.0;
          final tenure = int.tryParse(tenureCtrl.text) ?? 12;
          final emiPreview = AmortizationEngine.calculateEmi(
            principal: principal,
            annualInterestRate: selectedProduct.annualInterestRate,
            tenureInstallments: tenure > 0 ? tenure : 1,
            interestMethod: selectedProduct.interestMethod,
            frequency: selectedProduct.repaymentFrequency,
          );
          final feePreview = IndianFormatters.computeFeeWithGst(
            baseFee: principal * (selectedProduct.processingFeePct / 100.0),
            gstRatePct: selectedProduct.gstRatePct,
          );

          return AlertDialog(
            title: const Text('Originate New Loan + KYC'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Borrower Full Name *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: mobileCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Primary Mobile (+91) *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: panCtrl,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'PAN (ABCDE1234F)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: aadhaarCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Aadhaar (Last 4 / 12d)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: addressCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Shop / Residence Address *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            geoCaptured
                                ? 'GPS: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}'
                                : 'Using Madurai default pin',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final res = await LocationService.getCurrentLocation();
                            setStateDialog(() {
                              lat = res.latitude;
                              lng = res.longitude;
                              geoCaptured = !res.isFallback;
                            });
                          },
                          icon: const Icon(Icons.my_location, size: 16),
                          label: const Text('Pin GPS'),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    DropdownButtonFormField<LoanProductModel>(
                      value: selectedProduct,
                      decoration: const InputDecoration(
                        labelText: 'Loan Product Template',
                        border: OutlineInputBorder(),
                      ),
                      items: portfolio.products
                          .map(
                            (p) => DropdownMenuItem(
                              value: p,
                              child: Text(
                                '${p.productName} (${p.annualInterestRate}% ${p.interestMethod.label})',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setStateDialog(() => selectedProduct = v);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: principalCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setStateDialog(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Principal (₹) *',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: tenureCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setStateDialog(() {}),
                            decoration: InputDecoration(
                              labelText:
                                  'Tenure (${selectedProduct.repaymentFrequency.label})',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Estimated EMI: ${IndianFormatters.formatInr(emiPreview)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Fee: ${IndianFormatters.formatInr(feePreview.baseFee)} + '
                            '${selectedProduct.gstRatePct}% GST (${IndianFormatters.formatInr(feePreview.gstAmount)}) | '
                            'Net Disbursed: ${IndianFormatters.formatInr((principal - feePreview.totalFee).clamp(0, double.infinity))}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  final mobile = IndianFormatters.normalizeIndianMobile(
                    mobileCtrl.text,
                  );
                  final pan = panCtrl.text.trim().toUpperCase();
                  if (name.isEmpty || mobile.length < 10 || principal <= 0 || tenure <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Fill required borrower name, mobile, principal & tenure.'),
                      ),
                    );
                    return;
                  }
                  if (pan.isNotEmpty && !IndianFormatters.isValidPan(pan)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('PAN must match Indian format (e.g. ABCDE1234F).'),
                      ),
                    );
                    return;
                  }

                  final now = DateTime.now();
                  final borrower = BorrowerModel(
                    borrowerId: portfolio.generateNextBorrowerId(),
                    fullName: name,
                    mobilePrimary: mobile,
                    panNumber: pan,
                    aadhaarMasked: aadhaarCtrl.text.trim().isEmpty
                        ? ''
                        : IndianFormatters.maskAadhaar(aadhaarCtrl.text),
                    addressText: addressCtrl.text.trim().isEmpty
                        ? 'Madurai'
                        : addressCtrl.text.trim(),
                    latitude: lat,
                    longitude: lng,
                    geohash: GeoFilterEngine.encodeGeohash(lat, lng),
                    geoVerified: geoCaptured,
                    assignedAgentId: auth.currentUser?.uid ?? 'uid_agent_karthik',
                    createdAt: now,
                    updatedAt: now,
                  );

                  await portfolio.saveBorrower(borrower);
                  final createdLoan = await portfolio.originateNewLoan(
                    borrower: borrower,
                    product: selectedProduct,
                    principalSanctioned: principal,
                    tenureInstallments: tenure,
                    collectedByUid: auth.currentUser?.uid ?? 'uid_master_balaji',
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Originated ${createdLoan.loanId} with v1 schedule & disbursement ledger.',
                        ),
                      ),
                    );
                  }
                },
                child: const Text('Disburse Loan'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final portfolio = context.watch<LoanPortfolioProvider>();
    final auth = context.watch<AuthService>();

    final roleScoped = widget.agentIdFilter != null
        ? portfolio.loans
            .where((l) => l.assignedAgentId == widget.agentIdFilter)
            .toList()
        : auth.visibleLoansFor(portfolio.loans, portfolio.borrowers);

    final filtered = roleScoped.where((loan) {
      if (_bucketFilter != null && loan.agingBucket != _bucketFilter) {
        return false;
      }
      final b = portfolio.borrowerById(loan.borrowerId);
      return OmniSearchEngine.matches(
        loan: loan,
        borrower: b,
        query: _search,
      );
    }).toList();

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Omni-Search: Name, Mobile, Loan No, App No, Area, Pincode, PAN...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _bucketFilter == null,
                  onSelected: (_) => setState(() => _bucketFilter = null),
                ),
                const SizedBox(width: 6),
                for (final bucket in AgingBucket.values) ...[
                  FilterChip(
                    label: Text(bucket.label),
                    selected: _bucketFilter == bucket,
                    onSelected: (_) => setState(() => _bucketFilter = bucket),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No matching loans found.'))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    itemBuilder: (context, idx) {
                      final loan = filtered[idx];
                      final borrower = portfolio.borrowerById(loan.borrowerId);
                      final dpdColor = loan.dpd > 30
                          ? Colors.red.shade700
                          : loan.dpd > 0
                              ? Colors.amber.shade800
                              : Colors.green.shade700;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  LoanDetailScreen(loanId: loan.loanId),
                            ),
                          ),
                          leading: CircleAvatar(
                            backgroundColor: dpdColor.withValues(alpha: 0.14),
                            child: Text(
                              '${loan.dpd}d',
                              style: TextStyle(
                                color: dpdColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          title: Text(
                            borrower?.fullName ?? loan.borrowerId,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${loan.loanId} • EMI ${IndianFormatters.formatInr(loan.emiAmount, showDecimals: false)} • ${loan.status.label}',
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                IndianFormatters.formatInr(
                                  loan.totalOutstanding,
                                  showDecimals: false,
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                'v${loan.scheduleVersion} • ${loan.agingBucket.label}',
                                style: TextStyle(fontSize: 11, color: dpdColor),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showOriginateLoanDialog(portfolio, auth),
        icon: const Icon(Icons.add),
        label: const Text('New Loan'),
      ),
    );
  }
}



