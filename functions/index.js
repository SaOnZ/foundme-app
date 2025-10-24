/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

//const {setGlobalOptions} = require("firebase-functions");
//const {onRequest} = require("firebase-functions/https");
//const logger = require("firebase-functions/logger");

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
//setGlobalOptions({ maxInstances: 10 });

// Create and deploy your first functions
// https://firebase.google.com/docs/functions/get-started

// exports.helloWorld = onRequest((request, response) => {
//   logger.info("Hello logs!", {structuredData: true});
//   response.send("Hello from Firebase!");
// });


// Node 18+, Admin SDK
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onUserCreated } = require("firebase-functions/v2/auth");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
admin.initializeApp();

/** @param {string} uid */
async function getUserTokens(uid) {
  const snap = await admin.firestore().doc(`users/${uid}`).get();
  const data = snap.data() || {};
  return Array.isArray(data.fcmTokens) ? data.fcmTokens : [];
}


// New claim -> notify item owner
exports.notifyOwnerOnClaim = onDocumentCreated("claims/{id}", async (event) => {
  const claim = event.data.data();
  const ownerUid = String(claim.ownerUid || "");
  const claimerUid = String(claim.claimerUid || "");
  const itemId = String(claim.itemId || "");

  const tokens = await getUserTokens(ownerUid);
  if (!tokens.length) return;

  await admin.messaging().sendEachForMulticast({
    tokens,
    notification: {
      title: "New claim request",
      body:
        claim.message && claim.message.length
          ? claim.message
          : "Someone sent a claim on your item.",
    },
    data: {
      type: "claim",
      itemId,
      claimId: String(event.params.id),
      fromUid: claimerUid,
    },
  });
});

// New message -> notify the other participant
exports.notifyClaimParticipantOnMessage = onDocumentCreated(
  "messages/{id}",
  async (event) => {
    const msg = event.data.data();
    const claimId = String(msg.claimId || "");
    const sender = String(msg.senderUid || "");

    const snap = await admin.firestore().doc(`claims/${claimId}`).get();
    if (!snap.exists) return;
    const claim = snap.data();

    const targetUid =
      sender === String(claim.ownerUid)
        ? String(claim.claimerUid)
        : String(claim.ownerUid);

    const tokens = await getUserTokens(targetUid);
    if (!tokens.length) return;

    await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {
        title: "New message",
        body: msg.text || "New message on your claim",
      },
      data: {
        type: "chat",
        claimId,
        fromUid: sender,
      },
    });
  }
);


const BOOTSTRAP_ADMINS = new Set([
  "m.aimanzarif2003@gmail.com",  //TODO: put your email here
  // "foundme@example.com"
]);

exports.bootstarpAdminOnCreate = onUserCreated(async (event) => {
  const u = event.data;
try {
  if (u.email && BOOTSTRAP_ADMINS.has(u.email)) {
    await admin.auth().setCustomUserClaims(u.uid, { admin: true });
    await admin.firestore().doc(`users/${u.uid}`).set({ role: "admin" }, { merge: true });
  } else {
    await admin.firestore().doc(`users/${u.uid}`).set({ role: "user" }, { merge: true });
  }
  } catch (e) {
    console.error("bootstrapAdminOnCreate:", e);
  }
});


exports.setRole = onCall(async (req) => {
  if (!req.auth || req.auth.token?.admin !== true) {
    throw new HttpsError("permission-denied", "only admin can set roles");
  }
  const { uid, role } = req.data || {};
  if (!uid || !["admin", "user"].includes(role)) {
    throw new HttpsError("invalid-argument", "need uid and valid role");
  }
  await admin.auth().setCustomUserClaims(uid, { admin: role === "admin" });
  await admin.firestore().doc(`users/${uid}`).set({ role }, { merge: true });
  return { ok: true, uid, role };
});