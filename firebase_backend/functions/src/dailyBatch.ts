import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall, HttpsError } from "firebase-functions/v2/https";

admin.initializeApp();
const db = admin.firestore();

type AgingBucket =
  | "CURRENT"
  | "DPD_1_30"
  | "DPD_31_60"
  | "DPD_61_90"
  | "DPD_90_PLUS";

function bucketFromDpd(dpd: number): AgingBucket {
  if (dpd <= 0) return "CURRENT";
  if (dpd <= 30) return "DPD_1_30";
  if (dpd <= 60) return "DPD_31_60";
  if (dpd <= 90) return "DPD_61_90";
  return "DPD_90_PLUS";
}

function roundPaise(n: number): number {
  return Math.round(n * 100) / 100;
}

/**
 * Daily Midnight IST Batch Job (00:05 Asia/Kolkata):
 * 1. Recalculates DPD and aging buckets for all active/delinquent/restructured loans.
 * 2. Marks overdue OPEN PTPs as BROKEN.
 * 3. Assesses grace-period late fees (+18% GST) as immutable `LATE_FEE_ASSESSED` ledger entries.
 * 4. Evaluates `early_warning_flag` (missed 1st EMI, 2 consecutive partial pays, or broken PTP).
 */
export const dailyDelinquencyBatch = onSchedule(
  {
    schedule: "5 0 * * *",
    timeZone: "Asia/Kolkata",
  },
  async () => {
    const now = new Date();
    const todayMidnight = new Date(
      now.getFullYear(),
      now.getMonth(),
      now.getDate()
    );

    const productsSnap = await db.collection("loan_products").get();
    const products = new Map<string, FirebaseFirestore.DocumentData>();
    productsSnap.forEach((doc) => products.set(doc.id, doc.data()));

    const activeLoansSnap = await db
      .collection("loans")
      .where("status", "in", ["ACTIVE", "DELINQUENT", "RESTRUCTURED"])
      .get();

    for (const loanDoc of activeLoansSnap.docs) {
      const loan = loanDoc.data();
      const loanId = loanDoc.id;
      const product = products.get(loan.product_id) || {
        grace_period_days: 3,
        late_fee_type: "PERCENT_OVERDUE",
        late_fee_value: 2.0,
        gst_rate_pct: 18.0,
      };

      const scheduleSnap = await db
        .collection("installment_schedule")
        .where("loan_id", "==", loanId)
        .where("schedule_version", "==", loan.schedule_version || 1)
        .get();

      const logsSnap = await db
        .collection("collection_logs")
        .where("loan_id", "==", loanId)
        .get();

      const batch = db.batch();
      let maxDpd = 0;
      let overdueTotal = 0;
      let missedFirstEmi = false;
      let consecutivePartials = 0;
      let twoConsecutivePartials = false;

      const sortedRows = scheduleSnap.docs
        .map((d) => ({ id: d.id, ref: d.ref, data: d.data() }))
        .sort(
          (a, b) => (a.data.installment_no || 0) - (b.data.installment_no || 0)
        );

      for (const row of sortedRows) {
        const d = row.data;
        const pRem = Math.max(0, (d.principal_due || 0) - (d.principal_paid || 0));
        const iRem = Math.max(0, (d.interest_due || 0) - (d.interest_paid || 0));
        const fRem = Math.max(0, (d.fee_due || 0) - (d.fee_paid || 0));
        const fullyPaid = pRem + iRem + fRem <= 0.01;
        if (fullyPaid) {
          consecutivePartials = 0;
          continue;
        }

        const dueDate: Date = d.due_date?.toDate
          ? d.due_date.toDate()
          : new Date(d.due_date);
        const dueMidnight = new Date(
          dueDate.getFullYear(),
          dueDate.getMonth(),
          dueDate.getDate()
        );
        const daysPast = Math.floor(
          (todayMidnight.getTime() - dueMidnight.getTime()) /
            (1000 * 60 * 60 * 24)
        );
        const hasPartial =
          (d.principal_paid || 0) + (d.interest_paid || 0) + (d.fee_paid || 0) >
          0.01;

        if (hasPartial) {
          consecutivePartials++;
          if (consecutivePartials >= 2) twoConsecutivePartials = true;
        } else {
          consecutivePartials = 0;
        }

        if (daysPast > 0) {
          maxDpd = Math.max(maxDpd, daysPast);
          overdueTotal = roundPaise(overdueTotal + pRem + iRem);
          if (d.installment_no === 1) missedFirstEmi = true;
          batch.update(row.ref, {
            status: hasPartial ? "PARTIAL" : "OVERDUE",
          });
        } else if (daysPast === 0) {
          batch.update(row.ref, {
            status: hasPartial ? "PARTIAL" : "DUE_TODAY",
          });
        }
      }

      // Check broken PTPs
      let hasBrokenPtp = false;
      for (const logDoc of logsSnap.docs) {
        const log = logDoc.data();
        if (log.ptp_status === "BROKEN") {
          hasBrokenPtp = true;
        } else if (log.ptp_status === "OPEN" && log.ptp_date) {
          const ptpDate: Date = log.ptp_date?.toDate
            ? log.ptp_date.toDate()
            : new Date(log.ptp_date);
          if (ptpDate < todayMidnight) {
            batch.update(logDoc.ref, { ptp_status: "BROKEN" });
            hasBrokenPtp = true;
          }
        }
      }

      // Assess late fee (+18% GST) once DPD crosses grace period and no fee exists on oldest overdue row
      let feesAdded = 0;
      const graceDays = product.grace_period_days ?? 3;
      if (maxDpd > graceDays && overdueTotal > 0) {
        const oldestOverdue = sortedRows.find((r) => {
          const d = r.data;
          return (
            (d.principal_due || 0) - (d.principal_paid || 0) > 0.01 &&
            (d.fee_due || 0) <= 0.01
          );
        });
        if (oldestOverdue) {
          const baseFee =
            product.late_fee_type === "FLAT_INR"
              ? product.late_fee_value || 250
              : roundPaise(overdueTotal * ((product.late_fee_value || 2) / 100));
          const gst = roundPaise(baseFee * ((product.gst_rate_pct || 18) / 100));
          feesAdded = roundPaise(baseFee + gst);

          batch.update(oldestOverdue.ref, {
            fee_due: roundPaise((oldestOverdue.data.fee_due || 0) + feesAdded),
          });

          const txnRef = db.collection("transactions").doc();
          batch.set(txnRef, {
            txn_id: txnRef.id,
            loan_id: loanId,
            borrower_id: loan.borrower_id,
            txn_type: "LATE_FEE_ASSESSED",
            payment_mode: "SYSTEM_AUTO",
            reference_no: `LATEFEE-${todayMidnight.toISOString().slice(0, 10)}`,
            total_amount: feesAdded,
            allocated_fees: feesAdded,
            allocated_interest: 0,
            allocated_principal: 0,
            reversed_txn_id: null,
            collected_by_uid: "SYSTEM_BATCH",
            notes: `Auto late fee INR ${baseFee} + ${product.gst_rate_pct || 18}% GST INR ${gst}`,
            created_at: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      }

      const nextStatus =
        maxDpd > 0
          ? "DELINQUENT"
          : loan.schedule_version > 1
          ? "RESTRUCTURED"
          : "ACTIVE";

      batch.update(loanDoc.ref, {
        dpd: maxDpd,
        aging_bucket: bucketFromDpd(maxDpd),
        status: nextStatus,
        fees_outstanding: roundPaise((loan.fees_outstanding || 0) + feesAdded),
        early_warning_flag:
          missedFirstEmi || twoConsecutivePartials || hasBrokenPtp,
      });

      await batch.commit();
    }
  }
);

/**
 * Master-only callable to assign Firebase Auth Custom Claims (`MASTER`, `ADMIN`, `AGENT`).
 */
export const setUserRoleClaim = onCall(async (request) => {
  if (request.auth?.token?.role !== "MASTER") {
    throw new HttpsError(
      "permission-denied",
      "Only MASTER officers may update user role claims."
    );
  }
  const { targetUid, role } = request.data as {
    targetUid: string;
    role: "MASTER" | "ADMIN" | "AGENT";
  };
  if (!targetUid || !["MASTER", "ADMIN", "AGENT"].includes(role)) {
    throw new HttpsError("invalid-argument", "Invalid targetUid or role.");
  }
  await admin.auth().setCustomUserClaims(targetUid, { role });
  await db.collection("users").doc(targetUid).set({ role }, { merge: true });
  return { ok: true, targetUid, role };
});
