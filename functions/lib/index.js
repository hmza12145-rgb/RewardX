"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.admobSsv = exports.redeemGiftCard = exports.addGiftCard = exports.ensureProfile = exports.setAdminClaim = void 0;
const app_1 = require("firebase-admin/app");
const auth_1 = require("firebase-admin/auth");
const firestore_1 = require("firebase-admin/firestore");
const https_1 = require("firebase-functions/v2/https");
const logger = __importStar(require("firebase-functions/logger"));
(0, app_1.initializeApp)();
const db = (0, firestore_1.getFirestore)();
function requireUser(request) {
    if (!request.auth?.uid)
        throw new https_1.HttpsError("unauthenticated", "Please sign in.");
    return request.auth.uid;
}
function requireAdmin(request) {
    if (request.auth?.token?.admin !== true) {
        throw new https_1.HttpsError("permission-denied", "Admin access required.");
    }
}
// Run once from a trusted operator environment after replacing the UID.
// Never expose service-account credentials in the Flutter app.
exports.setAdminClaim = (0, https_1.onCall)(async (request) => {
    if (request.auth?.token?.owner !== true) {
        throw new https_1.HttpsError("permission-denied", "Project owner claim required.");
    }
    const uid = String(request.data?.uid ?? "");
    if (!uid)
        throw new https_1.HttpsError("invalid-argument", "uid required");
    await (0, auth_1.getAuth)().setCustomUserClaims(uid, { admin: true });
    return { ok: true };
});
// Idempotently initialize a newly signed-in user's profile. No client-supplied balance.
exports.ensureProfile = (0, https_1.onCall)(async (request) => {
    const uid = requireUser(request);
    const ref = db.collection("users").doc(uid);
    await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists) {
            tx.create(ref, {
                points: 0,
                email: request.auth?.token?.email ?? null,
                createdAt: firestore_1.FieldValue.serverTimestamp(),
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
            });
        }
    });
    return { ok: true };
});
// Admin-only stock import. Gift codes are stored in a private collection.
exports.addGiftCard = (0, https_1.onCall)(async (request) => {
    requireAdmin(request);
    const { code, label, productId, pointsCost, region } = request.data ?? {};
    if (![code, label, productId, region].every((v) => typeof v === "string" && v.trim())) {
        throw new https_1.HttpsError("invalid-argument", "Missing card fields.");
    }
    if (!Number.isInteger(pointsCost) || pointsCost <= 0) {
        throw new https_1.HttpsError("invalid-argument", "pointsCost must be a positive integer.");
    }
    const ref = db.collection("giftCards").doc();
    await ref.create({
        code: String(code).trim(),
        label: String(label).trim(),
        productId: String(productId).trim(),
        pointsCost,
        region: String(region).trim(),
        status: "available",
        createdAt: firestore_1.FieldValue.serverTimestamp(),
        createdBy: request.auth.uid,
    });
    return { ok: true, cardId: ref.id };
});
// Transactionally deduct points and reserve one available matching code.
exports.redeemGiftCard = (0, https_1.onCall)(async (request) => {
    const uid = requireUser(request);
    const productId = String(request.data?.productId ?? "");
    if (!productId)
        throw new https_1.HttpsError("invalid-argument", "productId required.");
    const userRef = db.collection("users").doc(uid);
    const cardsQuery = db.collection("giftCards")
        .where("productId", "==", productId)
        .where("status", "==", "available")
        .limit(1);
    return db.runTransaction(async (tx) => {
        const userSnap = await tx.get(userRef);
        if (!userSnap.exists)
            throw new https_1.HttpsError("failed-precondition", "Account profile not initialized.");
        const cardsSnap = await tx.get(cardsQuery);
        if (cardsSnap.empty)
            throw new https_1.HttpsError("not-found", "This reward is out of stock.");
        const cardDoc = cardsSnap.docs[0];
        const card = cardDoc.data();
        const balance = Number(userSnap.data()?.points ?? 0);
        const cost = Number(card.pointsCost);
        if (!Number.isInteger(cost) || cost <= 0)
            throw new https_1.HttpsError("internal", "Invalid reward configuration.");
        if (balance < cost)
            throw new https_1.HttpsError("failed-precondition", "Not enough points.");
        const redemptionRef = db.collection("redemptions").doc();
        const walletRef = userRef.collection("wallet").doc(redemptionRef.id);
        tx.update(userRef, { points: balance - cost, updatedAt: firestore_1.FieldValue.serverTimestamp() });
        tx.update(cardDoc.ref, {
            status: "claimed", claimedBy: uid, claimedAt: firestore_1.FieldValue.serverTimestamp()
        });
        tx.create(redemptionRef, {
            uid, cardId: cardDoc.id, productId, pointsCost: cost,
            status: "fulfilled", createdAt: firestore_1.FieldValue.serverTimestamp()
        });
        tx.create(walletRef, {
            label: card.label, code: card.code, region: card.region,
            claimedAt: firestore_1.FieldValue.serverTimestamp(), redemptionId: redemptionRef.id
        });
        return { ok: true, label: card.label, redemptionId: redemptionRef.id };
    });
});
// IMPORTANT SECURITY GATE:
// Do not enable AdMob SSV until this endpoint verifies Google's ECDSA signature,
// validates ad unit + timestamp + transaction_id, and deduplicates transaction_id.
// A client-side "rewarded" callback is NOT proof of a valid ad view.
exports.admobSsv = (0, https_1.onRequest)(async (_req, res) => {
    logger.error("AdMob SSV is not configured: refusing to credit points.");
    res.status(503).send("SSV verification not configured");
});
