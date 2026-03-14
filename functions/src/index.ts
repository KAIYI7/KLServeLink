/**
 * Import function triggers from their respective submodules:
 *
 * import {onCall} from "firebase-functions/v2/https";
 * import {onDocumentWritten} from "firebase-functions/v2/firestore";
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

//import {setGlobalOptions} from "firebase-functions";
//import {onRequest} from "firebase-functions/https";
//import * as logger from "firebase-functions/logger";

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { evaluatePricing, haversineKm, PricingRule, PricingCaps } from "./pricing";
import * as logger from "firebase-functions/logger";
import { onSchedule } from "firebase-functions/v2/scheduler";

// Start writing functions
// https://firebase.google.com/docs/functions/typescript

// For cost control, you can set the maximum number of containers that can be
// running at the same time. This helps mitigate the impact of unexpected
// traffic spikes by instead downgrading performance. This limit is a
// per-function limit. You can override the limit for each function using the
// `maxInstances` option in the function's options, e.g.
// `onRequest({ maxInstances: 5 }, (req, res) => { ... })`.
// NOTE: setGlobalOptions does not apply to functions using the v1 API. V1
// functions should each use functions.runWith({ maxInstances: 10 }) instead.
// In the v1 API, each function can only serve one request per container, so
// this will be the maximum concurrent request count.
// setGlobalOptions({ maxInstances: 10 });

// export const helloWorld = onRequest((request, response) => {
//   logger.info("Hello logs!", {structuredData: true});
//   response.send("Hello from Firebase!");
// });

admin.initializeApp();

const PAYMENT_TIMEOUT_MIN = 30;
const PAYMENT_TIMEOUT_MS = PAYMENT_TIMEOUT_MIN * 60 * 1000;

const KL_OFFSET_MS = 8 * 60 * 60 * 1000;
const LOCK_STEP_MIN = 5;
const LOCK_STEP_MS = LOCK_STEP_MIN * 60 * 1000;

const PENDING_REMIND_BEFORE_HOURS = 24;
const PENDING_AUTO_CANCEL_GRACE_MIN = 30;

const COMPLETE_REMIND_AFTER_HOURS = 6;     // remind provider 6h after expected end
const COMPLETE_AUTO_CANCEL_AFTER_DAYS = 3; // auto-cancel/refund after 3d

function tsToMs(ts: any): number | null {
  if (!ts) return null;
  if (ts instanceof Date) return ts.getTime();
  if (typeof ts.toDate === "function") return ts.toDate().getTime();
  return null;
}

function addHoursMs(ms: number, h: number) {
  return ms + h * 60 * 60 * 1000;
}

function addDaysMs(ms: number, d: number) {
  return ms + d * 24 * 60 * 60 * 1000;
}

function bookingEndMs(b: any): number | null {
  const startMs = tsToMs(b.scheduledAt);
  if (!startMs) return null;

  const hoursNum = Number(b.hours ?? 0);
  if (!Number.isFinite(hoursNum) || hoursNum <= 0) return null;

  const totalMinutes = Math.round(hoursNum * 60);
  return startMs + totalMinutes * 60 * 1000;
}

function pad2(n: number) { return n.toString().padStart(2, "0"); }
function pad4(n: number) { return n.toString().padStart(4, "0"); }

// Convert an instant to “KL-local” parts by shifting +8h and reading UTC fields.
function klPartsFromMs(ms: number) {
  const d = new Date(ms + KL_OFFSET_MS);
  return {
    y: d.getUTCFullYear(),
    m: d.getUTCMonth() + 1,
    d: d.getUTCDate(),
    hh: d.getUTCHours(),
    mm: d.getUTCMinutes(),
  };
}

function klDayKeyFromMs(ms: number) {
  const p = klPartsFromMs(ms);
  return `${p.y}${pad2(p.m)}${pad2(p.d)}`;
}

function klMinutesSinceMidnightFromMs(ms: number) {
  const p = klPartsFromMs(ms);
  return p.hh * 60 + p.mm; // 0..1439
}

function buildSlotLockRefs(providerId: string, startMs: number, endMs: number) {
  const refs: FirebaseFirestore.DocumentReference[] = [];
  for (let t = startMs; t < endMs; t += LOCK_STEP_MS) {
    const dayKey = klDayKeyFromMs(t);
    const slotMin = klMinutesSinceMidnightFromMs(t);
    const slotId = pad4(slotMin); // "0000".."1439"
    refs.push(
      admin.firestore()
        .collection("timeSlotLocks")
        .doc(`${providerId}_${dayKey}`)
        .collection("slots")
        .doc(slotId)
    );
  }
  return refs;
}

function overlaps(aStart: number, aEnd: number, bStart: number, bEnd: number) {
  return aStart < bEnd && aEnd > bStart;
}

async function releaseLocksForBooking(bookingId: string, b: any) {
  const providerId = String(b.providerId ?? "").trim();
  if (!providerId) return;

  const ts = b.scheduledAt;
  const startMs = (ts && typeof ts.toDate === "function")
    ? ts.toDate().getTime()
    : (ts instanceof Date ? ts.getTime() : null);

  if (!startMs) return;

  const hoursNum = Number(b.hours ?? 0);
  if (!Number.isFinite(hoursNum) || hoursNum <= 0) return;

  const totalMinutes = Math.round(hoursNum * 60);
  const endMs = startMs + totalMinutes * 60 * 1000;

  const refs = buildSlotLockRefs(providerId, startMs, endMs);
  if (refs.length === 0) return;

  // Batch delete in chunks
  const db = admin.firestore();
  let i = 0;
  while (i < refs.length) {
    const batch = db.batch();
    const slice = refs.slice(i, i + 450);
    for (const r of slice) batch.delete(r);
    await batch.commit();
    i += slice.length;
  }
}

function readPrefs(u: any): Record<string, any> {
  const raw = u?.notificationPrefs;
  return raw && typeof raw === "object" ? raw : {};
}

function prefBool(prefs: Record<string, any>, key: string, def = true): boolean {
  const v = prefs[key];
  return (v === undefined || v === null) ? def : v === true;
}

function isNotificationAllowedForUser(u: any, type: string): boolean {
  const prefs = readPrefs(u);

  const pushEnabled = prefBool(prefs, "pushEnabled", true);
  if (!pushEnabled) return false;

  const role = String(u?.role ?? "").toLowerCase();
  const t = String(type ?? "").toLowerCase();

  // Chat/messages
  if (t.includes("chat") || t.includes("message")) {
    return prefBool(prefs, "messages", prefBool(prefs, "chat", true));
  }

  // Reviews
  if (t.includes("review")) {
    return prefBool(prefs, "reviews", prefBool(prefs, "review", true));
  }

  // Bookings
  if (t.includes("booking")) {
    // Provider-only “new booking request”
    if (t === "booking_created" || t.includes("booking_created")) {
      if (role === "provider") {
        return prefBool(prefs, "newBookingRequests", prefBool(prefs, "bookingUpdates", true));
      }
      return prefBool(prefs, "bookingUpdates", prefBool(prefs, "booking", true));
    }

    return prefBool(prefs, "bookingUpdates", prefBool(prefs, "booking", true));
  }

  return prefBool(prefs, "promos", true);
}

async function systemCancelBooking(opts: {
  bookingRef: FirebaseFirestore.DocumentReference;
  bookingId: string;
  reason: string;
  refund: boolean;
}) {
  const { bookingRef, bookingId, reason, refund } = opts;

  let seekerId = "";
  let providerId = "";

  await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(bookingRef);
    if (!snap.exists) return;

    const b = snap.data() as any;

    const status = String(b.status ?? "").toLowerCase();
    if (status === "cancelled" || status === "declined") return;

    seekerId = String(b.seekerId ?? "").trim();
    providerId = String(b.providerId ?? "").trim();

    const p = (b.payment ?? {}) as any;
    const method = String(p.method ?? b.paymentMethod ?? "").toLowerCase();
    const state = String(p.state ?? "").toLowerCase();

    const now = admin.firestore.FieldValue.serverTimestamp();

    // default payment stays same unless refund requested + card is paid/authorized
    let paymentUpdate: any = p;

    if (refund && method === "card") {
      if (state === "authorized" || state === "captured") {
        paymentUpdate = {
          ...p,
          state: "refunded",
          refundedAt: now,
          refundReason: reason,
          refundedBy: "system",
        };
      }
    }

    tx.set(
      bookingRef,
      {
        status: "cancelled",
        cancelReason: reason,
        payment: paymentUpdate,
        updatedAt: now,
        cancelledAt: now,
        cancelledBy: "system",
      },
      { merge: true }
    );

    tx.create(bookingRef.collection("history").doc(), {
      at: now,
      title: "Auto-cancelled",
      subtitle: `System policy: ${reason}`,
      actorUid: "system",
    });
  });

  // Notify after transaction
  if (seekerId) {
    await pushInAppNotification({
      toUid: seekerId,
      title: "Booking auto-cancelled",
      body: `Your booking was automatically cancelled (${reason}).`,
      type: "booking_auto_cancelled",
      data: { bookingId, reason },
    });
  }

  if (providerId) {
    await pushInAppNotification({
      toUid: providerId,
      title: "Booking auto-cancelled",
      body: `A booking was automatically cancelled (${reason}).`,
      type: "booking_auto_cancelled_provider",
      data: { bookingId, reason },
    });
  }
}

export const remindPendingBookings1DayBefore = onSchedule(
  { schedule: "every 60 minutes", timeZone: "Asia/Kuala_Lumpur" },
  async () => {
    const db = admin.firestore();
    const now = Date.now();

    const fromMs = addHoursMs(now, PENDING_REMIND_BEFORE_HOURS - 1);
    const toMs   = addHoursMs(now, PENDING_REMIND_BEFORE_HOURS + 1);

    const snap = await db
      .collection("bookings")
      .where("status", "==", "pending")
      .where("scheduledAt", ">=", admin.firestore.Timestamp.fromMillis(fromMs))
      .where("scheduledAt", "<=", admin.firestore.Timestamp.fromMillis(toMs))
      .limit(200)
      .get();

    for (const doc of snap.docs) {
      const b = doc.data() as any;
      const bookingId = doc.id;

      const providerId = String(b.providerId ?? "").trim();
      if (!providerId) continue;

      // Gate with a field to avoid repeated reminders
      const already = b?.reminders?.pending1d === true;
      if (already) continue;

      await db.runTransaction(async (tx) => {
        const s = await tx.get(doc.ref);
        if (!s.exists) return;
        const bb = s.data() as any;
        if (String(bb.status ?? "") !== "pending") return;
        if (bb?.reminders?.pending1d === true) return;

        tx.set(doc.ref, { reminders: { ...(bb.reminders ?? {}), pending1d: true } }, { merge: true });
      });

      await pushInAppNotification({
        toUid: providerId,
        title: "Pending booking reminder",
        body: "You have a pending booking scheduled within 24 hours. Please accept or decline.",
        type: "booking_pending_reminder",
        data: { bookingId },
      });
    }
  }
);

export const autoCancelExpiredPendingBookings = onSchedule(
  { schedule: "every 30 minutes", timeZone: "Asia/Kuala_Lumpur" },
  async () => {
    const db = admin.firestore();
    const now = Date.now();
    const cutoffMs = now - PENDING_AUTO_CANCEL_GRACE_MIN * 60 * 1000;

    const snap = await db
      .collection("bookings")
      .where("status", "==", "pending")
      .where("scheduledAt", "<", admin.firestore.Timestamp.fromMillis(cutoffMs))
      .limit(200)
      .get();

    for (const doc of snap.docs) {
      await systemCancelBooking({
        bookingRef: doc.ref,
        bookingId: doc.id,
        reason: "provider_no_response",
        refund: false,
      });
      // slot locks will be released through onBookingUpdated trigger
    }
  }
);

export const handleOverdueServiceCompletion = onSchedule(
  { schedule: "every 6 hours", timeZone: "Asia/Kuala_Lumpur" },
  async () => {
    const db = admin.firestore();
    const now = Date.now();

    // Pull candidates in the last ~7 days
    const lookbackMs = now - 7 * 24 * 60 * 60 * 1000;

    const snap = await db
      .collection("bookings")
      .where("status", "in", ["accepted", "confirmed"])
      .where("scheduledAt", ">=", admin.firestore.Timestamp.fromMillis(lookbackMs))
      .where("scheduledAt", "<=", admin.firestore.Timestamp.fromMillis(now))
      .limit(200)
      .get();

    for (const doc of snap.docs) {
      const b = doc.data() as any;
      const bookingId = doc.id;

      const endMs = bookingEndMs(b);
      if (!endMs) continue;

      // reminder after end + X hours
      const remindAt = addHoursMs(endMs, COMPLETE_REMIND_AFTER_HOURS);
      const overdueForReminder = now >= remindAt;

      const providerId = String(b.providerId ?? "").trim();
      if (!providerId) continue;

      if (overdueForReminder && b?.reminders?.completeSoon !== true) {
        await db.runTransaction(async (tx) => {
          const s = await tx.get(doc.ref);
          if (!s.exists) return;
          const bb = s.data() as any;
          if (!["accepted", "confirmed"].includes(String(bb.status ?? ""))) return;
          if (bb?.reminders?.completeSoon === true) return;

          tx.set(doc.ref, { reminders: { ...(bb.reminders ?? {}), completeSoon: true } }, { merge: true });
        });

        await pushInAppNotification({
          toUid: providerId,
          title: "Reminder: update booking status",
          body: "Your service time has passed. Please update the booking status to Completed (or cancel if not fulfilled).",
          type: "booking_complete_reminder",
          data: { bookingId },
        });
      }

      // auto-cancel + refund after end + 3 days
      const cancelAt = addDaysMs(endMs, COMPLETE_AUTO_CANCEL_AFTER_DAYS);
      if (now >= cancelAt) {
        // Refund only for card paid/authorized scenarios
        const p = (b.payment ?? {}) as any;
        const method = String(p.method ?? b.paymentMethod ?? "").toLowerCase();
        const state = String(p.state ?? "").toLowerCase();

        const refund = (method === "card") && (state === "authorized" || state === "captured");

        await systemCancelBooking({
          bookingRef: doc.ref,
          bookingId,
          reason: "no_completion_update",
          refund,
        });
      }
    }
  }
);

async function trySendFcm(
  toUid: string,
  title: string,
  body: string,
  type: string,
  data?: Record<string, any>
) {
  const userRef = admin.firestore().collection("users").doc(toUid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) return;

  const u = userSnap.data() || {};

  if (!isNotificationAllowedForUser(u, type)) return;

  const token = (u.fcmToken ?? "").toString().trim();
  if (!token) return;

  const flat: Record<string, string> = {
    type: String(type),
    title: String(title),
    body: String(body),
  };

  if (data) {
    for (const [k, v] of Object.entries(data)) {
      flat[k] = typeof v === "string" ? v : JSON.stringify(v);
    }
  }

  try {
    await admin.messaging().send({
      token,
      notification: { title, body },
      data: flat,
      android: {
        priority: "high",
        notification: {
          channelId: "kl_default_channel",
        },
      },
    });
  } catch (e: any) {
    const code = e?.errorInfo?.code || e?.code || "";

    // Clean up dead tokens
    if (code === "messaging/registration-token-not-registered") {
      await userRef.set(
        { fcmToken: admin.firestore.FieldValue.delete() },
        { merge: true }
      );
    }

    logger.warn("FCM send failed", { toUid, code });
  }
}

async function pushInAppNotification(params: {
  toUid: string;
  title: string;
  body: string;
  type: string;
  data?: Record<string, any>;
}) {
  const { toUid, title, body, type, data } = params;
  if (!toUid) return;

  const userRef = admin.firestore().collection("users").doc(toUid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) return;

  const u = userSnap.data() || {};

  if (!isNotificationAllowedForUser(u, type)) return;

  await userRef.collection("notifications").add({
    title,
    body,
    type,
    data: data ?? {},
    read: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await trySendFcm(toUid, title, body, type, data);
}

type CreateBookingPayload = {
  serviceId: string;
  providerId: string;

  scheduledAtMs: number;
  hours: number;

  addressId: string;
  locationText: string;
  locationArea: string;
  locationLat?: number | null;
  locationLng?: number | null;
  locationGeohash?: string | null;

  paymentMethodId: string;
};

export const createBookingVerified = onCall(async (req) => {
  // Require auth
  const auth = req.auth;
  if (!auth?.uid) throw new HttpsError("unauthenticated", "Login required.");

  const data = req.data as CreateBookingPayload;

  // Validation
  const serviceId = String(data.serviceId ?? "").trim();
  const providerId = String(data.providerId ?? "").trim();
  const hoursRaw = Number(data.hours ?? 0);
  const scheduledAtMs = Number(data.scheduledAtMs ?? 0);

  if (!serviceId) throw new HttpsError("invalid-argument", "Missing serviceId");
  if (!providerId) throw new HttpsError("invalid-argument", "Missing providerId");

  if (!Number.isFinite(hoursRaw)) {
    throw new HttpsError("invalid-argument", "Invalid hours");
  }

  const totalMinutes = Math.round(hoursRaw * 60);

  if (totalMinutes < 60 || totalMinutes > 24 * 60) {
    throw new HttpsError("invalid-argument", "Invalid duration");
  }

  if (totalMinutes % 5 !== 0) {
    throw new HttpsError("invalid-argument", "Duration must be in 5-minute steps");
  }

  const hours = totalMinutes / 60;

  if (!Number.isFinite(scheduledAtMs) || scheduledAtMs <= 0) {
    throw new HttpsError("invalid-argument", "Invalid scheduledAtMs");
  }

  const scheduledAt = new Date(scheduledAtMs);
  if (scheduledAt.getTime() < Date.now() - 5 * 60 * 1000) {
    throw new HttpsError("invalid-argument", "scheduledAt is in the past");
  }

  // Load service doc
  const svcRef = admin.firestore().collection("services").doc(serviceId);
  const svcSnap = await svcRef.get();
  if (!svcSnap.exists) throw new HttpsError("not-found", "Service not found.");

  const svc = svcSnap.data() ?? {};
  const svcProviderId = String(svc["providerId"] ?? "");
  const status = String(svc["status"] ?? "");
  const isDeleted = Boolean(svc["isDeleted"] ?? false);

  if (svcProviderId !== providerId) {
    throw new HttpsError("failed-precondition", "Provider mismatch.");
  }
  if (status !== "active" || isDeleted) {
    throw new HttpsError("failed-precondition", "Service not active.");
  }

  // Auto-lock setting (default true)
  const autoLockTimeSlots = (svc["autoLockTimeSlots"] ?? true) === true;

  // Booking window in ms
  const startMs = scheduledAt.getTime();
  const endMs = startMs + totalMinutes * 60 * 1000;

  // Compute floor price
  const price = Number(svc["price"] ?? 0);
  const discount = Number(svc["discount"] ?? 0);
  const floorPrice = Math.max(
    0,
    Math.min(
      1e12,
      price * (1.0 - Math.min(Math.max(discount, 0), 100) / 100)
    )
  );

  // Read included duration from service
  const durH = Number(
    svc["durationH"] ?? svc["durationHours"] ?? svc["durationHour"] ?? 0
  );
  const durM = Number(
    svc["durationM"] ?? svc["durationMins"] ?? svc["durationMinutes"] ?? 0
  );

  const includedMinutes = Math.max(0, Math.round(durH * 60 + durM));
  const includedHours = includedMinutes / 60.0;

  // Read hourlyRate / rules / caps
  let hourlyRate = Number(svc["hourlyRate"] ?? 0);

  // fallback: derive hourly from package price / includedHours
  if (!Number.isFinite(hourlyRate) || hourlyRate <= 0) {
    hourlyRate =
      includedHours > 0 ? (price / includedHours) : 22;
  }

  const rulesRaw = Array.isArray(svc["pricingRules"]) ? svc["pricingRules"] : [];
  const rules = rulesRaw
    .filter((x: any) => x && typeof x === "object")
    .map((x: any) => ({
      id: String(x.id ?? "rule"),
      label: x.label ? String(x.label) : undefined,
      type: x.type === "percent" ? "percent" : "fixed",
      value: Number(x.value ?? 0),
      when: x.when ?? {},
      priority: x.priority != null ? Number(x.priority) : undefined,
      exclusiveGroup: x.exclusiveGroup != null ? String(x.exclusiveGroup) : undefined,
    })) as PricingRule[];

  const capsRaw =
    (svc["pricingCaps"] && typeof svc["pricingCaps"] === "object")
      ? svc["pricingCaps"]
      : undefined;

  const caps: PricingCaps | undefined = capsRaw
    ? {
        maxPercent: capsRaw.maxPercent != null ? Number(capsRaw.maxPercent) : undefined,
        maxFixed: capsRaw.maxFixed != null ? Number(capsRaw.maxFixed) : undefined,

        maxSurchargePercent: capsRaw.maxSurchargePercent != null ? Number(capsRaw.maxSurchargePercent) : undefined,
        maxDiscountPercent:  capsRaw.maxDiscountPercent  != null ? Number(capsRaw.maxDiscountPercent)  : undefined,
        maxSurchargeFixed:   capsRaw.maxSurchargeFixed   != null ? Number(capsRaw.maxSurchargeFixed)   : undefined,
        maxDiscountFixed:    capsRaw.maxDiscountFixed    != null ? Number(capsRaw.maxDiscountFixed)    : undefined,
        minTotal:            capsRaw.minTotal            != null ? Number(capsRaw.minTotal)            : undefined,
        maxTotal:            capsRaw.maxTotal            != null ? Number(capsRaw.maxTotal)            : undefined,
      }
    : undefined;

  // Compute distance on server (if coords exist)
  const providerLat = svc["lat"];
  const providerLng = svc["lng"];

  const locLat = data.locationLat ?? null;
  const locLng = data.locationLng ?? null;

  let distanceKm: number | null = null;
  if (
    typeof providerLat === "number" &&
    typeof providerLng === "number" &&
    typeof locLat === "number" &&
    typeof locLng === "number"
  ) {
    distanceKm = haversineKm(locLat, locLng, providerLat, providerLng);
  }


  // Evaluate pricing
  const quote = evaluatePricing({
    floorPrice,
    hourlyRate,
    scheduledAt,
    hours,               // booked hours (total)
    includedHours,       // package included hours
    distanceKm,
    rules,
    caps,
  });

  // Write booking doc (server-source-of-truth)
  const seekerId = auth.uid;
  const seekerName = String(req.auth?.token?.name ?? "Seeker");

  // Overlap check against existing bookings
  if (autoLockTimeSlots) {
    const qSnap = await admin.firestore()
      .collection("bookings")
      .where("providerId", "==", providerId)
      .where("status", "in", ["pending", "accepted", "confirmed", "completed"])
      .where("scheduledAt", "<", admin.firestore.Timestamp.fromMillis(endMs))
      .where(
        "scheduledAt",
        ">=",
        admin.firestore.Timestamp.fromMillis(startMs - 24 * 60 * 60 * 1000)
      )
      .orderBy("scheduledAt", "asc")
      .get();

    for (const d of qSnap.docs) {
      const m = d.data() as any;

      const ts = m.scheduledAt;
      const exStartMs =
        (ts && typeof ts.toDate === "function") ? ts.toDate().getTime()
        : (ts instanceof Date ? ts.getTime() : null);

      if (!exStartMs) continue;

      const exHours = Number(m.hours ?? 0);
      if (!Number.isFinite(exHours) || exHours <= 0) continue;

      const exEndMs = exStartMs + exHours * 60 * 60 * 1000;

      if (overlaps(startMs, endMs, exStartMs, exEndMs)) {
        throw new HttpsError(
          "failed-precondition",
          "Selected time is not available. Please choose another slot."
        );
      }
    }
  }

  const bookingRef = admin.firestore().collection("bookings").doc();

  const paymentMethodId = String(data.paymentMethodId ?? "cash");
  const paymentMeta = (data as any).paymentMeta ?? {};

  const payment =
    paymentMethodId === "card"
      ? {
          method: "card",
          state: "unpaid",
          amount: quote.total,
          currency: "MYR",
          cardBrand: paymentMeta.cardBrand ?? null,
          cardLast4: paymentMeta.cardLast4 ?? null,
          payoutStatus: "none",
        }
      : {
          method: "cash",
          state: "cash_due",
          amount: quote.total,
          currency: "MYR",
          payoutStatus: "none",
        };

  const lockRefs = autoLockTimeSlots
    ? buildSlotLockRefs(providerId, startMs, endMs)
    : [];

  try {
    await admin.firestore().runTransaction(async (tx) => {
      // Create slot locks first
      // tx.create fails if any lock already exists.
      if (autoLockTimeSlots) {
        for (const ref of lockRefs) {
          tx.create(ref, {
            bookingId: bookingRef.id,
            providerId,
            serviceId,
            seekerId,
            startMs,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      }

      // Create booking
      tx.set(bookingRef, {
        providerId,
        seekerId,
        seekerName,
        serviceId,
        serviceName: String(svc["name"] ?? ""),
        scheduledAt: admin.firestore.Timestamp.fromDate(scheduledAt),
        status: "pending",

        // location / address
        addressId: String(data.addressId ?? ""),
        locationText: String(data.locationText ?? ""),
        locationArea: String(data.locationArea ?? ""),
        locationLat: locLat,
        locationLng: locLng,
        locationGeohash: data.locationGeohash ?? null,
        providerLat: typeof providerLat === "number" ? providerLat : null,
        providerLng: typeof providerLng === "number" ? providerLng : null,
        distanceKm: distanceKm,

        paymentMethod: paymentMethodId,
        payment,

        // lock metadata
        lockedSlots: autoLockTimeSlots,
        lockStepMin: autoLockTimeSlots ? LOCK_STEP_MIN : null,

        // verified pricing
        totalAmount: quote.total,
        floorPrice: quote.baseFloor,
        hourlyRate: quote.hourlyRate,
        hours: quote.hours,
        includedMinutes,
        includedHours,
        billableHours: (quote as any).billableHours ?? null,
        rulesDelta: quote.rulesDelta,
        pricingLines: quote.lines.map((l) => ({
          ruleId: l.ruleId,
          label: l.label,
          amount: l.amount,
          note: l.note ?? null,
        })),
        pricingRulesSnapshot: rulesRaw,
        pricingVersion: 2,
        pricingVerified: true,

        serviceRating: Number(svc["ratingAvg"] ?? svc["rating"] ?? 0),
        isReviewed: false,

        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // History
      tx.create(bookingRef.collection("history").doc(), {
        at: admin.firestore.FieldValue.serverTimestamp(),
        title: "New Booking",
        subtitle: "Created by seeker",
        actorUid: seekerId,
      });
    });
  } catch (e: any) {
    // If any lock doc already existed, tx.create will fail.
    const code = e?.code;

    if (code === 6 || code === "already-exists" || code === "ALREADY_EXISTS") {
      throw new HttpsError(
        "failed-precondition",
        "Selected time is no longer available. Please choose another slot."
      );
    }
    throw e;
  }

  return {
    bookingId: bookingRef.id,
    totalAmount: quote.total,
    distanceKm,
    quote,
  };
});

export const payForBooking = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Login required.");

  const bookingId = String(req.data?.bookingId ?? "").trim();
  if (!bookingId) throw new HttpsError("invalid-argument", "Missing bookingId");

  // PaymentMeta
  const metaRaw = req.data?.paymentMeta;
  let metaBrand: string | null = null;
  let metaLast4: string | null = null;
  if (metaRaw && typeof metaRaw === "object") {
    const mm: any = metaRaw;
    const b = mm.cardBrand;
    const l4 = mm.cardLast4;
    if (typeof b === "string" && b.trim()) metaBrand = b.trim();
    if (typeof l4 === "string" && l4.trim()) metaLast4 = l4.trim();
  }

  const ref = admin.firestore().collection("bookings").doc(bookingId);

  await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Booking not found");

    const b = snap.data() as any;

    // Only seeker can pay
    if (String(b.seekerId ?? "") !== uid) {
      throw new HttpsError("permission-denied", "Not your booking");
    }

    // Must be accepted first
    if (String(b.status ?? "") !== "accepted") {
      throw new HttpsError("failed-precondition", "Booking not accepted yet");
    }

    const p = (b.payment ?? {}) as any;
    const method = String(p.method ?? b.paymentMethod ?? "").toLowerCase();
    const state = String(p.state ?? "").toLowerCase();

    if (method !== "card") {
      throw new HttpsError("failed-precondition", "Not a card booking");
    }
    if (state !== "unpaid") {
      throw new HttpsError("failed-precondition", "Already paid or not payable");
    }

    tx.set(
      ref,
      {
        status: "confirmed",
        payment: {
          ...p,
          state: "authorized",
          cardBrand: metaBrand ?? p.cardBrand ?? null,
          cardLast4: metaLast4 ?? p.cardLast4 ?? null,
          authorizedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    tx.create(ref.collection("history").doc(), {
      at: admin.firestore.FieldValue.serverTimestamp(),
      title: "Payment authorized",
      subtitle: "Seeker paid after provider acceptance",
      actorUid: uid,
    });
  });

  return { ok: true };
});

export const confirmServiceCompleted = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Login required.");

  const bookingId = String(req.data?.bookingId ?? "").trim();
  if (!bookingId) throw new HttpsError("invalid-argument", "Missing bookingId");

  const ref = admin.firestore().collection("bookings").doc(bookingId);

  await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Booking not found");

    const b = snap.data() as any;

    if (String(b.seekerId ?? "") !== uid) {
      throw new HttpsError("permission-denied", "Not your booking");
    }

    const status = String(b.status ?? "");
    if (status !== "completed") {
      throw new HttpsError("failed-precondition", "Booking not completed yet");
    }

    const p = (b.payment ?? {}) as any;

    if (String(p.method ?? "") !== "card") {
      throw new HttpsError("failed-precondition", "Not a card booking");
    }

    const pState = String(p.state ?? "");
    if (pState !== "awaiting_seeker_confirm" && pState !== "authorized") {
      throw new HttpsError("failed-precondition", "Booking not ready for confirmation");
    }

    tx.set(
      ref,
      {
        payment: {
          ...p,
          state: "captured",
          seekerConfirmedAt: admin.firestore.FieldValue.serverTimestamp(),
          capturedAt: admin.firestore.FieldValue.serverTimestamp(),
          payoutStatus: "none",
        },
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    tx.create(ref.collection("history").doc(), {
      at: admin.firestore.FieldValue.serverTimestamp(),
      title: "Service confirmed",
      subtitle: "Seeker confirmed completion (card captured)",
      actorUid: uid,
    });
  });

  return { ok: true };
});

export const confirmCashReceived = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Login required.");

  const bookingId = String(req.data?.bookingId ?? "").trim();
  if (!bookingId) throw new HttpsError("invalid-argument", "Missing bookingId");

  const ref = admin.firestore().collection("bookings").doc(bookingId);

  await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Booking not found");

    const b = snap.data() as any;

    if (String(b.providerId ?? "") !== uid) {
      throw new HttpsError("permission-denied", "Not your booking");
    }

    const status = String(b.status ?? "");
    if (status !== "completed") {
      throw new HttpsError("failed-precondition", "Booking not completed yet");
    }

    const p = (b.payment ?? {}) as any;

    if (String(p.method ?? "") !== "cash") {
      throw new HttpsError("failed-precondition", "Not a cash booking");
    }

    tx.set(
      ref,
      {
        payment: {
          ...p,
          state: "cash_received",
          providerCashConfirmedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    tx.create(ref.collection("history").doc(), {
      at: admin.firestore.FieldValue.serverTimestamp(),
      title: "Cash received",
      subtitle: "Provider confirmed cash payment",
      actorUid: uid,
    });
  });

  return { ok: true };
});

export const cancelBookingWithRefund = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Login required.");

  const bookingId = String(req.data?.bookingId ?? "").trim();
  const reason = String(req.data?.reason ?? "").trim();
  if (!bookingId) throw new HttpsError("invalid-argument", "Missing bookingId");

  const ref = admin.firestore().collection("bookings").doc(bookingId);

  await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Booking not found");

    const b = snap.data() as any;

    const isSeeker = String(b.seekerId ?? "") === uid;
    const isProvider = String(b.providerId ?? "") === uid;
    if (!isSeeker && !isProvider) {
      throw new HttpsError("permission-denied", "Not allowed");
    }

    const newStatus = isSeeker ? "cancelled" : "declined";

    const p = (b.payment ?? {}) as any;
    const method = String(p.method ?? b.paymentMethod ?? "");
    const state = String(p.state ?? "").toLowerCase();

    const now = admin.firestore.FieldValue.serverTimestamp();

    let paymentUpdate: any | null = null;

    if (method === "card") {
      // unpaid => no refund needed
      if (state === "authorized" || state === "captured") {
        paymentUpdate = {
          ...p,
          state: "refunded",
          refundedAt: now,
          refundReason:
            reason || (isSeeker ? "seeker_cancelled" : "provider_declined"),
          refundedBy: uid,
        };
      }
    }

    tx.set(
      ref,
      {
        status: newStatus,
        payment: paymentUpdate ?? p,
        updatedAt: now,
        cancelledAt: now,
        cancelledBy: uid,
      },
      { merge: true }
    );

    tx.create(ref.collection("history").doc(), {
      at: now,
      title: "Booking cancelled",
      subtitle: paymentUpdate ? "Refund processed" : "Cancelled before payment",
      actorUid: uid,
    });
  });

  return { ok: true };
});

export const sweepUnpaidAcceptedBookings = onSchedule(
  { schedule: "every 10 minutes", timeZone: "Asia/Kuala_Lumpur" },
  async () => {
    const cutoff = admin.firestore.Timestamp.fromMillis(
      Date.now() - 30 * 60 * 1000
    );

    const q = await admin
      .firestore()
      .collection("bookings")
      .where("status", "==", "accepted")
      .where("payment.state", "==", "unpaid")
      .where("acceptedAt", "<", cutoff)
      .limit(200)
      .get();

    if (q.empty) return;

    const batch = admin.firestore().batch();

    const notifySeekerIds: { uid: string; bookingId: string }[] = [];

    q.docs.forEach((doc) => {
      const b = doc.data() as any;
      const seekerId = String(b.seekerId ?? "").trim();
      if (seekerId) notifySeekerIds.push({ uid: seekerId, bookingId: doc.id });

      batch.set(
        doc.ref,
        {
          status: "cancelled",
          cancelReason: "payment_timeout",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
          cancelledBy: "system",
        },
        { merge: true }
      );

      batch.create(doc.ref.collection("history").doc(), {
        at: admin.firestore.FieldValue.serverTimestamp(),
        title: "Auto-cancelled",
        subtitle: "Payment timeout (not paid after acceptance)",
        actorUid: "system",
      });
    });

    await batch.commit();

    for (const n of notifySeekerIds) {
      await pushInAppNotification({
        toUid: n.uid,
        title: "Booking cancelled",
        body: "Your booking was automatically cancelled because payment was not completed within 30 minutes.",
        type: "booking_auto_cancelled",
        data: { bookingId: n.bookingId, reason: "payment_timeout" },
      });
    }
  }
);

export const onBookingCreated = onDocumentCreated("bookings/{bookingId}", async (event) => {
  const snap = event.data;
  if (!snap) return;

  const b = snap.data() as any;
  const providerId = b?.providerId;
  if (!providerId) return;

  const serviceName = (b?.serviceName ?? "Service").toString();
  const locationText = (b?.locationText ?? "").toString();

  await pushInAppNotification({
    toUid: providerId,
    title: "New booking request",
    body: `${serviceName}${locationText ? " • " + locationText : ""}`.trim(),
    type: "booking_created",
    data: { bookingId: event.params.bookingId },
  });
});

export const onBookingUpdated = onDocumentUpdated("bookings/{bookingId}", async (event) => {
  const before = event.data?.before?.data() as any;
  const after = event.data?.after?.data() as any;
  if (!before || !after) return;

  const beforeStatus = (before.status ?? "").toString();
  const afterStatus = (after.status ?? "").toString();
  if (beforeStatus === afterStatus) return;

  // Release locked slots if booking was cancelled/declined
  if (
    (afterStatus === "cancelled" || afterStatus === "declined") &&
    (beforeStatus !== "cancelled" && beforeStatus !== "declined")
  ) {
    await releaseLocksForBooking(event.params.bookingId, after);
  }

  const seekerId = after.seekerId;
  const providerId = after.providerId;

  if (seekerId) {
    await pushInAppNotification({
      toUid: seekerId,
      title: "Booking update",
      body: `Your booking is now: ${afterStatus}`,
      type: "booking_status",
      data: { bookingId: event.params.bookingId, status: afterStatus },
    });
  }

  if (providerId && afterStatus === "cancelled") {
    await pushInAppNotification({
      toUid: providerId,
      title: "Booking cancelled",
      body: "A seeker cancelled their booking.",
      type: "booking_cancelled",
      data: { bookingId: event.params.bookingId },
    });
  }

  // If booking just got accepted, remind seeker to pay (card + unpaid only)
  if (afterStatus === "accepted" && beforeStatus !== "accepted") {
    const seekerId = String(after.seekerId ?? "").trim();
    if (seekerId) {
      const p = (after.payment ?? {}) as any;
      const method = String(p.method ?? after.paymentMethod ?? "").toLowerCase();
      const state = String(p.state ?? "").toLowerCase();

      // Only warn for card bookings that are still unpaid
      if (method === "card" && state === "unpaid") {
        // Compute deadline text from acceptedAt if present
        const acceptedAtTs = after.acceptedAt;
        const acceptedAtMs =
          (acceptedAtTs && typeof acceptedAtTs.toDate === "function")
            ? acceptedAtTs.toDate().getTime()
            : null;

        const deadlineMs = acceptedAtMs ? (acceptedAtMs + PAYMENT_TIMEOUT_MS) : null;

        const body =
          deadlineMs
            ? `Please complete your payment within ${PAYMENT_TIMEOUT_MIN} minutes to avoid automatic cancellation.`
            : `Please complete your payment within ${PAYMENT_TIMEOUT_MIN} minutes to avoid automatic cancellation.`;

        await pushInAppNotification({
          toUid: seekerId,
          title: "Payment required",
          body,
          type: "booking_payment_deadline",
          data: {
            bookingId: event.params.bookingId,
            minutes: PAYMENT_TIMEOUT_MIN,
          },
        });
      }
    }
  }

});

export const onMessageCreated = onDocumentCreated(
  "threads/{threadId}/messages/{messageId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const msg = snap.data() as any;
    const senderId = (msg?.senderId ?? "").toString().trim();
    if (!senderId) return;

    const threadId = event.params.threadId;

    // Read thread to find other participant
    const threadRef = admin.firestore().doc(`threads/${threadId}`);
    const threadSnap = await threadRef.get();
    if (!threadSnap.exists) return;

    const t = (threadSnap.data() ?? {}) as any;
    const participants: string[] = Array.isArray(t.participants) ? t.participants.map(String) : [];

    // Find the other user (2-person threads)
    const toUid = participants.find((uid) => uid && uid !== senderId);
    if (!toUid) {
      logger.warn("No recipient found", { threadId, senderId, participants });
      return;
    }

    // Avoid notifying if sender sends empty text + no media
    const text = (msg?.text ?? "").toString().trim();
    const body =
      text ||
      (msg?.type === "image" ? "Sent an image" :
       msg?.type === "audio" ? "Sent a voice message" :
       "You received a new message");

    await pushInAppNotification({
      toUid,
      title: "New message",
      body,
      type: "chat_message",
      data: { peerUid: senderId, threadId, messageId: event.params.messageId },
    });
  }
);

export const onReviewCreated = onDocumentCreated(
  "services/{serviceId}/reviews/{reviewId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const r = snap.data() as any;
    const providerId = r?.providerId;
    if (!providerId) return;

    await pushInAppNotification({
      toUid: providerId,
      title: "New review received",
      body: `${(r?.seekerName ?? "Someone").toString()} left a review.`,
      type: "review_received",
      data: { serviceId: event.params.serviceId, reviewId: event.params.reviewId },
    });
  }
);
