import 'package:flutter/material.dart';

import '../models/borrower_model.dart';
import '../models/collection_log_model.dart';
import '../models/loan_model.dart';
import '../services/location_service.dart';
import '../utils/indian_formatters.dart';

/// Bottom sheet for logging Field Visits, Calls, WhatsApp Reminders, and Promise-to-Pay (PTP)
/// with automatic GPS coordinates stamp.
class PtpLogBottomSheet extends StatefulWidget {
  const PtpLogBottomSheet({
    super.key,
    required this.loan,
    required this.borrower,
    required this.agentId,
    required this.onSave,
  });

  final LoanModel loan;
  final BorrowerModel borrower;
  final String agentId;
  final Future<void> Function(CollectionLogModel log) onSave;

  static Future<void> show(
    BuildContext context, {
    required LoanModel loan,
    required BorrowerModel borrower,
    required String agentId,
    required Future<void> Function(CollectionLogModel log) onSave,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PtpLogBottomSheet(
        loan: loan,
        borrower: borrower,
        agentId: agentId,
        onSave: onSave,
      ),
    );
  }

  @override
  State<PtpLogBottomSheet> createState() => _PtpLogBottomSheetState();
}

class _PtpLogBottomSheetState extends State<PtpLogBottomSheet> {
  CollectionActionType _actionType = CollectionActionType.fieldVisit;
  CollectionDisposition _disposition = CollectionDisposition.ptpConfirmed;
  DateTime _ptpDate = DateTime.now().add(const Duration(days: 2));
  DateTime _nextFollowup = DateTime.now().add(const Duration(days: 1));
  late final TextEditingController _ptpAmountController;
  final TextEditingController _notesController = TextEditingController();
  double? _visitLat;
  double? _visitLng;
  bool _capturingGps = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ptpAmountController = TextEditingController(
      text: widget.loan.emiAmount.toStringAsFixed(0),
    );
    _captureGps();
  }

  @override
  void dispose() {
    _ptpAmountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _captureGps() async {
    setState(() => _capturingGps = true);
    final res = await LocationService.getCurrentLocation();
    if (!mounted) return;
    setState(() {
      _visitLat = res.latitude;
      _visitLng = res.longitude;
      _capturingGps = false;
    });
  }

  Future<void> _pickDate({required bool isPtpDate}) async {
    final initial = isPtpDate ? _ptpDate : _nextFollowup;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 180)),
    );
    if (picked == null) return;
    setState(() {
      if (isPtpDate) {
        _ptpDate = picked;
        _nextFollowup = picked;
      } else {
        _nextFollowup = picked;
      }
    });
  }

  Future<void> _submit() async {
    final isPtp = _disposition == CollectionDisposition.ptpConfirmed;
    final ptpAmount = isPtp ? double.tryParse(_ptpAmountController.text) : null;
    if (isPtp && (ptpAmount == null || ptpAmount <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid Promise-to-Pay amount.')),
      );
      return;
    }

    setState(() => _saving = true);
    final now = DateTime.now();
    final log = CollectionLogModel(
      logId: 'LOG-${now.millisecondsSinceEpoch}',
      loanId: widget.loan.loanId,
      borrowerId: widget.borrower.borrowerId,
      agentId: widget.agentId,
      actionType: _actionType,
      disposition: _disposition,
      ptpDate: isPtp ? _ptpDate : null,
      ptpAmount: ptpAmount,
      ptpStatus: isPtp ? PtpStatus.open : PtpStatus.notApplicable,
      visitLat: _actionType == CollectionActionType.fieldVisit ? _visitLat : null,
      visitLng: _actionType == CollectionActionType.fieldVisit ? _visitLng : null,
      notes: _notesController.text.trim().isEmpty
          ? '${_actionType.label}: ${_disposition.label}'
          : _notesController.text.trim(),
      nextFollowupAt: _nextFollowup,
      createdAt: now,
    );

    await widget.onSave(log);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isPtp = _disposition == CollectionDisposition.ptpConfirmed;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Log Collection / PTP',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Text(
              '${widget.borrower.fullName} • ${widget.loan.loanId} (${widget.loan.dpd} DPD)',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<CollectionActionType>(
              value: _actionType,
              decoration: const InputDecoration(
                labelText: 'Action Type',
                border: OutlineInputBorder(),
              ),
              items: CollectionActionType.values
                  .map(
                    (a) => DropdownMenuItem(value: a, child: Text(a.label)),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _actionType = v);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<CollectionDisposition>(
              value: _disposition,
              decoration: const InputDecoration(
                labelText: 'Disposition',
                border: OutlineInputBorder(),
              ),
              items: CollectionDisposition.values
                  .map(
                    (d) => DropdownMenuItem(value: d, child: Text(d.label)),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _disposition = v);
              },
            ),
            if (isPtp) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _ptpAmountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'PTP Amount (₹)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(isPtpDate: true),
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text('PTP: ${IndianFormatters.formatDate(_ptpDate)}'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(isPtpDate: false),
                    icon: const Icon(Icons.schedule, size: 16),
                    label: Text(
                      'Follow-up: ${IndianFormatters.formatDate(_nextFollowup)}',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (_actionType == CollectionActionType.fieldVisit)
                  Chip(
                    avatar: Icon(
                      _capturingGps ? Icons.gps_not_fixed : Icons.gps_fixed,
                      size: 16,
                    ),
                    label: Text(
                      _visitLat != null
                          ? '${_visitLat!.toStringAsFixed(4)}, ${_visitLng!.toStringAsFixed(4)}'
                          : 'Locating...',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Field / Call Notes',
                hintText: 'Summarize customer response, landmark, or commitment...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: const Text('Save Collection Log'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
