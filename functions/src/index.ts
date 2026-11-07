import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

initializeApp();
const db = getFirestore();

function requireUser(request: { auth?: { uid: string } | null }): string {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Please sign in.");
  return request.auth.uid;
}
function requireAdmin(request: { auth?: { token?: Record<string, unknown> } | null }) {
  if (request.auth?.token?.admin !== true) {
    throw new HttpsError("permission-denied", "Admin access required.");
  }
}

// Run once from a trusted operator environment after replacing the UID.
// Never expose service-account credentials in the Flutter app.
export const setAdminClaim = onCall(async (request) => {
  if (request.auth?.token?.owner !== true) {
    throw new HttpsError("permission-denied", "Project owner claim required.");
  }
  const uid = String(request.data?.uid ?? "");
  if (!uid) throw new HttpsError("invalid-argument", "uid required");
  await getAuth().setCustomUserClaims(uid, { admin: true });
  return { ok: true };
});


// Idempotently initialize a newly signed-in user's profile. No client-supplied balance.
export const ensureProfile = onCall(async (request) => {
  const uid = requireUser(request);
  const ref = db.collection("users").doc(uid);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      tx.create(ref, {
        points: 0,
        email: request.auth?.token?.email ?? null,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  });
  return { ok: true };
});

// Admin-only stock import. Gift codes are stored in a private collection.
export const addGiftCard = onCall(async (request) => {
  requireAdmin(request);
  const { code, label, productId, pointsCost, region } = request.data ?? {};
  if (![code, label, productId, region].every((v) => typeof v === "string" && v.trim())) {
    throw new HttpsError("invalid-argument", "Missing card fields.");
  }
  if (!Number.isInteger(pointsCost) || pointsCost <= 0) {
    throw new HttpsError("invalid-argument", "pointsCost must be a positive integer.");
  }
  const ref = db.collection("giftCards").doc();
  await ref.create({
    code: String(code).trim(),
    label: String(label).trim(),
    productId: String(productId).trim(),
    pointsCost,
    region: String(region).trim(),
    status: "available",
    createdAt: FieldValue.serverTimestamp(),
    createdBy: request.auth!.uid,
  });
  return { ok: true, cardId: ref.id };
});

// Transactionally deduct points and reserve one available matching code.
export const redeemGiftCard = onCall(async (request) => {
  const uid = requireUser(request);
  const productId = String(request.data?.productId ?? "");
  if (!productId) throw new HttpsError("invalid-argument", "productId required.");

  const userRef = db.collection("users").doc(uid);
  const cardsQuery = db.collection("giftCards")
    .where("productId", "==", productId)
    .where("status", "==", "available")
    .limit(1);

  return db.runTransaction(async (tx) => {
    const userSnap = await tx.get(userRef);
    if (!userSnap.exists) throw new HttpsError("failed-precondition", "Account profile not initialized.");
    const cardsSnap = await tx.get(cardsQuery);
    if (cardsSnap.empty) throw new HttpsError("not-found", "This reward is out of stock.");
    const cardDoc = cardsSnap.docs[0];
    const card = cardDoc.data();
    const balance = Number(userSnap.data()?.points ?? 0);
    const cost = Number(card.pointsCost);
    if (!Number.isInteger(cost) || cost <= 0) throw new HttpsError("internal", "Invalid reward configuration.");
    if (balance < cost) throw new HttpsError("failed-precondition", "Not enough points.");

    const redemptionRef = db.collection("redemptions").doc();
    const walletRef = userRef.collection("wallet").doc(redemptionRef.id);
    tx.update(userRef, { points: balance - cost, updatedAt: FieldValue.serverTimestamp() });
    tx.update(cardDoc.ref, {
      status: "claimed", claimedBy: uid, claimedAt: FieldValue.serverTimestamp()
    });
    tx.create(redemptionRef, {
      uid, cardId: cardDoc.id, productId, pointsCost: cost,
      status: "fulfilled", createdAt: FieldValue.serverTimestamp()
    });
    tx.create(walletRef, {
      label: card.label, code: card.code, region: card.region,
      claimedAt: FieldValue.serverTimestamp(), redemptionId: redemptionRef.id
    });
    return { ok: true, label: card.label, redemptionId: redemptionRef.id };
  });
});

// IMPORTANT SECURITY GATE:
// Do not enable AdMob SSV until this endpoint verifies Google's ECDSA signature,
// validates ad unit + timestamp + transaction_id, and deduplicates transaction_id.
// A client-side "rewarded" callback is NOT proof of a valid ad view.
export const admobSsv = onRequest(async (_req, res) => {
  logger.error("AdMob SSV is not configured: refusing to credit points.");
  res.status(503).send("SSV verification not configured");
});
