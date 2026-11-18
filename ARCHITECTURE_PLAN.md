# ARCHITECTURE_PLAN.md — Saro Devi Enterprises (Special Finance Unit)
## Unified Loan Management, Field GPS Locator & Collections System

### 1. System Vision & Stack
Consolidate the fragmented Flutter prototypes (`Batch 2`, `Batch 4`, `loan_locator_app (6).txt`, `loan_locator_app (11).txt`) into a single production **Flutter (Android/Web)** application backed by **Firebase (Firestore + Auth + Storage + Cloud Functions)**—merging **GPS Field Geo-Location** with a full **End-to-End Lending & Collections Engine**.

* **Frontend:** Flutter (Dart), `provider` / `riverpod` state management, `google_maps_flutter`, `geolocator`, `excel` (for `.xlsx` import), `pdf` + `printing` (for KFS, schedules, receipts, payoff letters), `url_launcher` (one-tap WhatsApp/Phone/Google Maps navigation).
* **Backend & Persistence:** Cloud Firestore (structured as the 6 relational collections below), Firebase Auth (Custom Claims RBAC replacing hardcoded email checks), Cloud Functions (daily midnight DPD/late-fee/PTP batch scheduler).
* **Locale & Indian Compliance:** Currency in **INR (`₹`)** with Indian lakh/crore formatting, `DD/MM/YYYY` dates, KYC fields (**PAN**, **Masked Aadhaar**, **GSTIN**, **Bank A/C + IFSC**), payment rails (**UPI, NEFT/RTGS, e-NACH, Cash**), **18% GST** split on processing/penal fees, and **Key Fact Statement (KFS)** generation.

---

### 2. Six-Table / Collection Relational Data Model

#### Table 1: `borrowers`
Stores customer master, KYC, and geo-coordinates (migrating and extending `ExcelService` fields `CustomerName`, `MobileNo`, `Location`, `LatLong`).
* `borrower_id` (PK, auto-generated `SDE-CUST-XXXX`)
* `full_name` (String, required)
* `mobile_primary` (String, E.164 `+91...`, indexed)
* `mobile_alternate` (String, nullable)
* `business_name` (String, nullable)
* `pan_number` (String, validated regex `[A-Z]{5}[0-9]{4}[A-Z]{1}`)
* `aadhaar_masked` (String, `XXXX-XXXX-1234`)
* `gstin` (String, nullable)
* `kyc_doc_urls` (List<String> — Firebase Storage links for photo ID / shop photo)
* `address_text` (String)
* `latitude` (Double) & `longitude` (Double) & `geohash` (String — for 50 km radius queries)
* `geo_verified` (Boolean — true once field agent pins location on-site)
* `assigned_agent_id` (FK -> `users.uid`)
* `created_at`, `updated_at` (Timestamp)

#### Table 2: `loan_products`
Reusable product templates controlling interest math and fee rules.
* `product_id` (PK)
* `product_name` (String — e.g., *Quick Business Loan*, *Asset-Backed LAP*, *Daily/Weekly Micro Loan*)
* `interest_method` (Enum: `REDUCING_BALANCE`, `FLAT_RATE`)
* `annual_interest_rate` (Double, %)
* `repayment_frequency` (Enum: `DAILY`, `WEEKLY`, `MONTHLY`)
* `max_tenure_installments` (Int)
* `processing_fee_pct` (Double) & `gst_rate_pct` (Double, default `18.0`)
* `grace_period_days` (Int, default `3`)
* `late_fee_type` (Enum: `FLAT_INR`, `PERCENT_OVERDUE`) & `late_fee_value` (Double)
* `at_risk_dpd_threshold` (Int, default `30`)
* `is_active` (Boolean)

#### Table 3: `loans`
Master loan account record (migrating `ApplicationNo`, `LoanNo`, `Amount` from `.xlsx` imports).
* `loan_id` (PK, formatted `SDE-LN-XXXX`)
* `application_no` (String, unique)
* `borrower_id` (FK -> `borrowers.borrower_id`, indexed)
* `product_id` (FK -> `loan_products.product_id`)
* `assigned_agent_id` (FK -> `users.uid`, indexed)
* `principal_sanctioned` (Double, INR)
* `processing_fee_amount` (Double) & `gst_amount` (Double)
* `net_disbursed_amount` (Double)
* `interest_rate_annual` (Double)
* `interest_method` (Enum: `REDUCING_BALANCE`, `FLAT_RATE`)
* `tenure_installments` (Int)
* `emi_amount` (Double)
* `disbursement_date` (Timestamp)
* `first_due_date` (Timestamp)
* `maturity_date` (Timestamp)
* `schedule_version` (Int, starts at `1`; increments on restructuring)
* `principal_outstanding` (Double)
* `interest_outstanding` (Double)
* `fees_outstanding` (Double)
* `dpd` (Int — Days Past Due, updated daily; `0` if current)
* `aging_bucket` (Enum: `CURRENT`, `DPD_1_30`, `DPD_31_60`, `DPD_61_90`, `DPD_90_PLUS`)
* `status` (Enum: `PENDING_APPROVAL`, `ACTIVE`, `DELINQUENT`, `RESTRUCTURED`, `CLOSED`, `WRITTEN_OFF`)
* `early_warning_flag` (Boolean — auto-triggered on missed 1st EMI, 2 consecutive partial pays, or broken PTP)

#### Table 4: `installment_schedule`
Versioned amortization schedule rows. Never overwritten on restructure—old version marked `SUPERSEDED`.
* `installment_id` (PK)
* `loan_id` (FK -> `loans.loan_id`, indexed)
* `schedule_version` (Int, matches `loans.schedule_version`)
* `installment_no` (Int: `1..N`)
* `due_date` (Timestamp, indexed)
* `opening_principal` (Double)
* `principal_due` (Double)
* `interest_due` (Double)
* `fee_due` (Double)
* `total_due` (Double)
* `principal_paid` (Double, default `0`)
* `interest_paid` (Double, default `0`)
* `fee_paid` (Double, default `0`)
* `paid_date` (Timestamp, nullable)
* `status` (Enum: `UPCOMING`, `DUE_TODAY`, `PARTIAL`, `PAID`, `OVERDUE`, `SUPERSEDED`)

#### Table 5: `transactions` (Immutable Append-Only Ledger)
Every rupee movement creates a permanent record. Reversals insert a `REVERSAL` contra-entry referencing `reversed_txn_id`.
* `txn_id` (PK)
* `loan_id` (FK -> `loans.loan_id`, indexed)
* `borrower_id` (FK -> `borrowers.borrower_id`)
* `txn_type` (Enum: `DISBURSEMENT`, `REPAYMENT`, `PREPAYMENT`, `LATE_FEE_ASSESSED`, `WAIVER`, `REVERSAL`, `WRITE_OFF`, `RECOVERY`)
* `payment_mode` (Enum: `UPI`, `NEFT_RTGS`, `ENACH`, `CASH`, `CHEQUE`, `SYSTEM_AUTO`)
* `reference_no` (String — UTR / UPI Ref / Cheque No / Receipt No)
* `total_amount` (Double)
* `allocated_fees` (Double)
* `allocated_interest` (Double)
* `allocated_principal` (Double)
* `reversed_txn_id` (String, nullable — links bounce/reversal to original entry)
* `collected_by_uid` (FK -> `users.uid`)
* `geo_lat` (Double, nullable) & `geo_lng` (Double, nullable — captures field collection coordinates)
* `receipt_pdf_url` (String, nullable)
* `created_at` (Timestamp, server-enforced immutable)

#### Table 6: `collection_logs`
Field visit & tele-calling CRM linked to geo-location and Promise-to-Pay (PTP) tracking.
* `log_id` (PK)
* `loan_id` (FK -> `loans.loan_id`, indexed)
* `borrower_id` (FK -> `borrowers.borrower_id`)
* `agent_id` (FK -> `users.uid`)
* `action_type` (Enum: `CALL`, `FIELD_VISIT`, `WHATSAPP_REMINDER`, `LEGAL_NOTICE`)
* `disposition` (Enum: `PTP_CONFIRMED`, `PARTIAL_COLLECTED`, `REFUSED_TO_PAY`, `CUSTOMER_UNAVAILABLE`, `WRONG_ADDRESS`, `DISPUTE`)
* `ptp_date` (Timestamp, nullable)
* `ptp_amount` (Double, nullable)
* `ptp_status` (Enum: `OPEN`, `KEPT`, `BROKEN`, `NOT_APPLICABLE`)
* `visit_lat` (Double, nullable) & `visit_lng` (Double, nullable — verifies agent visited borrower pin)
* `notes` (String)
* `next_followup_at` (Timestamp)
* `created_at` (Timestamp)

---

### 3. Core Functional Modules & Business Logic

1. **Role-Based Access Control (`users` collection + Firebase Claims):**
   * `MASTER`: Full portfolio visibility, product creation, loan restructuring approval, write-offs, reversal authorization, agent management.
   * `ADMIN`: Branch/portfolio oversight, Excel bulk import/mapping, payment verification, reports export.
   * `AGENT`: Assigned borrowers only, Geo-Map route view, field visit check-ins, Call/PTP logging, field payment capture.
2. **Smart Excel (`.xlsx`) Ingestion Pipeline (Upgrading `ExcelService`):**
   * Retain backward compatibility with the 7-column sheet (`Location`, `ApplicationNo`, `LoanNo`, `CustomerName`, `Amount`, `LatLong`, `MobileNo`), parse `LatLong` safely into `(latitude, longitude)`, deduplicate against existing `borrowers` by `mobile_primary` / `loan_id`, and generate initial `loans` + `installment_schedule` records.
3. **Geo-Map & Field Route Locator (Upgrading `MapPage`):**
   * Color-coded map pins by loan health: **Green** (`CURRENT`), **Amber** (`DPD 1–30` or `PTP Due Today`), **Red** (`DPD 31+` or `Broken PTP`).
   * Filter pins by **50 km Haversine radius**, **Assigned Agent**, **Aging Bucket**, or **PTP Due Today**, with one-tap Google Maps turn-by-turn navigation and on-site GPS check-in verification.
4. **Portfolio & Officer Dashboard:**
   * KPIs: Total Deployed Capital (`₹`), Active Loans, Principal & Interest Collected (MTD/YTD), **Portfolio at Risk (PAR > 30 days %)**, Aging Breakdown (`Current`, `1–30`, `31–60`, `61–90`, `90+`), and Agent Collection Efficiency leaderboard.
5. **Individual Loan 360° File & "What-If" Prepayment Simulator:**
   * Displays borrower KYC, geo-pin, principal-vs-interest payoff chart, versioned schedule, and immutable ledger history.
   * **What-If Simulator:** Given a lump-sum prepayment `ΔP` or recurring extra EMI `ΔE`, computes side-by-side:
     * **Option A (Reduce Tenure):** Keep EMI constant, solve for reduced `N'`, display installments saved & total interest saved (`₹`).
     * **Option B (Reduce EMI):** Keep remaining tenure `N_rem` constant, solve for lower `EMI'`, display monthly cashflow relief & total interest saved (`₹`).
   * One-click **Payoff Quote PDF** and **Non-Destructive Restructuring (`v1 -> v2`)**.
6. **Collections Queue & Automated Daily Batch Job:**
   * Priority queue ordered by `early_warning_flag` -> `Broken PTP` -> `DPD descending`, with 1-tap **Call**, **WhatsApp Reminder**, **Log PTP**, or **Record Payment**.
   * Waterfall allocation on payment: `Fees/Penalties -> Accrued Interest -> Principal Overdue -> Current Principal`.

---

### 4. Target Folder Structure (`loan_locator_app/lib/`)
Cleanly replace the 1-line stubs and consolidate code from `Batch 2`, `Batch 4`, and `.txt` snapshots into:
```text
lib/
├── main.dart
├── firebase/
│   └── firebase_options.dart
├── models/
│   ├── borrower_model.dart
│   ├── loan_product_model.dart
│   ├── loan_model.dart
│   ├── installment_model.dart
│   ├── transaction_model.dart
│   └── collection_log_model.dart
├── engines/
│   ├── amortization_engine.dart      # Reducing/Flat EMI, What-If simulator, Restructuring v2
│   ├── delinquency_engine.dart       # DPD, aging buckets, PAR %, Early Warning flags
│   └── geo_filter_engine.dart        # Haversine radius & route sorting
├── services/
│   ├── auth_service.dart
│   ├── firestore_loan_service.dart   # Atomic batch writes for ledger + schedule updates
│   ├── excel_import_service.dart     # Upgraded 7+ column parser & validator
│   ├── location_service.dart
│   └── pdf_export_service.dart       # Receipts, KFS, Payoff Letters, Arrears Reports
├── screens/
│   ├── auth/login_screen.dart
│   ├── dashboard/master_dashboard.dart
│   ├── dashboard/agent_home_screen.dart
│   ├── map/field_locator_map_screen.dart
│   ├── loans/loan_list_screen.dart
│   ├── loans/loan_detail_screen.dart
│   ├── loans/what_if_simulator_screen.dart
│   ├── collections/collections_queue_screen.dart
│   └── admin/excel_import_screen.dart
└── widgets/
    ├── borrower_map_card.dart
    ├── aging_bucket_chart.dart
    └── ptp_log_bottom_sheet.dart