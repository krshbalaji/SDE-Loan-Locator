# SDE-Loan-Locator Operational Runbook

## 1. Domain & Financial Standards
- **Domain**: Indian NBFC retail lending (Housing Finance, Loan Against Property, collections, aging/DPD, and KFS/CSV/PDF exports).
- **Monetary Precision**: All monetary amounts round to paise (`IndianFormatters.roundPaise`) with finite guards (`NaN`/`Infinity` -> `0.0`).
- **Display & Reporting**: Indian Rupee formatting (`₹`, lakhs/crores via `IndianFormatters`) and Indian Financial Year (`Apr-Mar`) alongside Calendar Year reporting.
- **Ledger & Schedules**: Immutable append-only `transactions` (reversals post contra-entries rather than mutating history) and versioned `installment_schedule` rows.

## 2. Firestore Collections & Security
- `app_config` — Signed-in read; executive-only write.
- `users` — Self or admin+ read; privilege fields (`role`, `is_active`, `allowed_features`) guarded from self-escalation.
- `loan_products` — Active-user read; executive-only write.
- `borrowers`, `loans`, `installment_schedule` — Role/feature scoped access; executive-only deletion.
- `transactions`, `collection_logs`, `maker_checker_requests`, `audit_logs` — Append-only / non-destructive rules (`update`/`delete` blocked where immutable).

## 3. Release & Verification Checklist
1. Run `dart analyze` and confirm zero errors or warnings.
2. Run `flutter test` to verify amortization, waterfall/delinquency, formatting, and portfolio state guards.
3. Verify `firestore.rules` and `firebase_backend/firestore.rules` match before deploying rules.
4. Smoke-test sign-in, loan origination, payment/reversal, KFS/CSV export, and loan deletion.
