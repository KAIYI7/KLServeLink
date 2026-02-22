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
  const token = (u.fcmToken ?? "").toString().trim();
  if (!token) return;

  // Prefs gate (safe defaults = true)
  const prefs =
    u.notificationPrefs && typeof u.notificationPrefs === "object"
      ? u.notificationPrefs
      : {};
  const pushEnabled = (prefs.pushEnabled ?? true) === true;

  const cat =
    type.includes("chat") ? "chat" :
    type.includes("booking") ? "booking" :
    type.includes("review") ? "review" :
    "general";

  const catEnabled = (prefs[cat] ?? true) === true;
  if (!pushEnabled || !catEnabled) return;

  // FCM data must be string:string
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

  await admin
    .firestore()
    .collection("users")
    .doc(toUid)
    .collection("notifications")
    .add({
      title,
      body,
      type,
      data: data ?? {},
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

  // Try sending FCM push too (if token exists)
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

  // Read hourlyRate / rules / caps
  const hourlyRate = Number(svc["hourlyRate"] ?? 22); // fallback only if missing
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
    hours,
    distanceKm,
    rules,
    caps,
  });

  // Write booking doc (server-source-of-truth)
  const seekerId = auth.uid;
  const seekerName = String(req.auth?.token?.name ?? "Seeker");

  const bookingRef = admin.firestore().collection("bookings").doc();

  const paymentMethodId = String(data.paymentMethodId ?? "cash");
  const paymentMeta = (data as any).paymentMeta ?? {};

  const payment =
    paymentMethodId === "card"
      ? {
          method: "card",
          state: "authorized",
          amount: quote.total,
          currency: "MYR",
          cardBrand: paymentMeta.cardBrand ?? null,
          cardLast4: paymentMeta.cardLast4 ?? null,
          authorizedAt: admin.firestore.FieldValue.serverTimestamp(),
          payoutStatus: "none",
        }
      : {
          method: "cash",
          state: "cash_due",
          amount: quote.total,
          currency: "MYR",
          payoutStatus: "none",
        };

  await bookingRef.set({
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

    // verified pricing
    totalAmount: quote.total,
    floorPrice: quote.baseFloor,
    hourlyRate: quote.hourlyRate,
    hours: quote.hours,
    rulesDelta: quote.rulesDelta,
    pricingLines: quote.lines.map((l) => ({
      ruleId: l.ruleId,
      label: l.label,
      amount: l.amount,
      note: l.note ?? null,
    })),
    pricingRulesSnapshot: rulesRaw,
    pricingVersion: 1,
    pricingVerified: true,

    serviceRating: Number(svc["ratingAvg"] ?? svc["rating"] ?? 0),
    isReviewed: false,

    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await bookingRef.collection("history").add({
    at: admin.firestore.FieldValue.serverTimestamp(),
    title: "New Booking",
    subtitle: "Created by seeker (verified)",
    actorUid: seekerId,
  });

  return {
    bookingId: bookingRef.id,
    totalAmount: quote.total,
    distanceKm,
    quote,
  };
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
