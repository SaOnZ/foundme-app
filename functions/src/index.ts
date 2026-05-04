import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onCall, HttpsError } from  "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

// Initialize the Firebase Admin SDK
admin.initializeApp();
const db = admin.firestore();
const messaging = admin.messaging();

// ===================================================================
//  NEW FUNCTION: submitReview (Callable Function)
// ===================================================================

export const submitReview = onCall(async (request) => {
  // 1. Get data from the app
  const { claimId, roleToReview, rating } = request.data;
  const callerUid = request.auth?.uid;

  // 2. Authentication & Validation
  if (!callerUid) {
    throw new HttpsError(
      "unauthenticated",
      "You must be logged in to leave a review.",
    );
  }
  if (!claimId || !roleToReview || !rating) {
    throw new HttpsError(
      "invalid-argument",
      "Missing required fields (claimId, roleToReview, rating).",
    );
  }
  if (rating < 0.5 || rating > 5) {
    throw new HttpsError(
      "invalid-argument",
      "Rating must be between 0.5 and 5.",
    );
  }

  // 3. Get the claim document
  const claimRef = db.collection("claims").doc(claimId);
  const claimDoc = await claimRef.get();
  if (!claimDoc.exists) {
    throw new HttpsError(
      "not-found", 
      "Claim not found.",
    );
  }
  const claim = claimDoc.data()!;

  //4. Security Check: Is the caller part of this claim?
  if (callerUid !== claim.ownerUid && callerUid !== claim.claimerUid) {
    throw new HttpsError(
      "permission-denied",
      "You are not authorized to review this claim.",
    );
  }

  // 5. Determine who is being reviewed
  let recipientUid: String;
  let reviewFieldToUpdate: string;

  if (roleToReview === "claimer") {
    recipientUid = claim.claimerUid;
    reviewFieldToUpdate = "ownerHasReviewed"; //The owner is reviewing
    if (callerUid !== claim.ownerUid) {
      throw new HttpsError(
        "permission-denied",
        "You are not the owner.",
      );
    }
    if (claim.ownerHasReviewed === true) {
      throw new HttpsError(
        "failed-precondition",
        "You have already reviewed the claimer.",
      );
    }
  } else if (roleToReview === "owner") {
    recipientUid = claim.ownerUid;
    reviewFieldToUpdate = "claimerHasReviewed"; //The claimer is reviewing
    if (callerUid !== claim.claimerUid) {
      throw new HttpsError(
        "permission-denied",
        "You are not the claimer.",
      );
    }
    if (claim.claimerHasReviewed === true) {
      throw new HttpsError(
        "failed-precondition",
        "You have already reviewed this owner.",
      );
    }
  } else {
    throw new HttpsError(
      "invalid-argument",
      "roleToReview must be either 'claimer' or 'owner'.",
    );
  }
  
  // 6. Run a transaction to update the rating and claim
  try {
    await db.runTransaction(async (transaction) => {
      const userRef = db.collection("users").doc(String(recipientUid));
      const userDoc = await transaction.get(userRef);

      if (!userDoc.exists) {
        throw new HttpsError(
          "not-found", "User not found."
        );
      }

      // Get current rating data (or defaults)
      const userData = userDoc.data()!;
      const oldAvg = (userData.averageRating as number) || 0;
      const oldCt = (userData.ratingCount as number) || 0;

      // Calculate new rating
      const newTotalRating = oldAvg * oldCt + rating;
      const newCt = oldCt + 1;
      const newAvg = newTotalRating / newCt;

      // Update the user's profile
      transaction.update(userRef, {
        averageRating: newAvg,
        ratingCount: newCt,
      });

      // Update the claim to mark this review as complete
      transaction.update(claimRef, {
        [reviewFieldToUpdate]: true,
      });
    });

    logger.log('Review submitted for user ${recipientUid} by ${callerUid}.');
    return { success: true, message: "Review submitted!" };
  } catch (error) {
    logger.error("Error submitting review:", error);
    throw new HttpsError(
      "internal", "Error submitting review."
    );
  }
});

//  NEW FUNCTION: disableUser (Callable Function)
// 1. Get the caller's ID and the target's ID
export const disableUser = onCall(async (request) => {
  const callerUid = request.auth?.uid;
  const { uid: uidToDisable } = request.data;

  // 2. Security check: must be authenticated
  if (!callerUid) {
    throw new HttpsError(
      "unauthenticated",
      "You must be logged in to perform this action.",
    );
  }
  // 3. Security check: must be an admin
  const callerDoc = await db.collection("users").doc(callerUid).get();
  if (callerDoc.data()?.role !== "admin") {
    throw new HttpsError(
      "permission-denied",
      "You must be and admin to perform this action.",
    );
  }

  // 4. Validation
  if (!uidToDisable) {
    throw new HttpsError("invalid-argument", "No 'uid' provided to disable.");
  }
  if (callerUid == uidToDisable) {
    throw new HttpsError("failed-precondition", "admins cannot disable themselves.");
  }

  try {
    // 5. Disable the user in Firebase Authentication
    // This blocks them from logging in.
    await admin.auth().updateUser(uidToDisable, {
      disabled: true,
    });

    // 6. Update their Firestore role
    // Helps app UI know they are disabled.
    await db.collection("users").doc(uidToDisable).update({
      role: "disabled",
    });

    logger.log('Admin: ${callerUid} successfully disabled user ${uidToDisable}');
    return { success: true, message: "User has been disabled." };
  } catch (error) {
    logger.error('Error disabling user ${uidToDisable}:', error);
    throw new HttpsError("internal", "An error occured while disabling the user.");
  }
})

// ===================================================================
//  sendAdminNotification (Callable Function)
//  Replaces the previous client-side FCM v1 path that bundled a
//  service-account key in the app. Admins call this; the function
//  verifies admin role and sends via the project's default service
//  account. Used for post approval/rejection notifications.
// ===================================================================
export const sendAdminNotification = onCall(async (request) => {
  const callerUid = request.auth?.uid;
  const { targetUid, title, body, data } = request.data;

  if (!callerUid) {
    throw new HttpsError("unauthenticated", "You must be logged in.");
  }

  const callerDoc = await db.collection("users").doc(callerUid).get();
  if (callerDoc.data()?.role !== "admin") {
    throw new HttpsError("permission-denied", "Admin only.");
  }

  if (!targetUid || !title || !body) {
    throw new HttpsError(
      "invalid-argument",
      "Missing targetUid, title, or body.",
    );
  }

  // Collect target tokens. Schema is mid-migration: some users have a
  // fcmTokens array, some still carry a legacy fcmToken string.
  const targetDoc = await db.collection("users").doc(targetUid).get();
  const targetData = targetDoc.data() || {};
  const tokens: string[] = [];
  if (Array.isArray(targetData.fcmTokens)) {
    for (const t of targetData.fcmTokens) {
      if (typeof t === "string" && t && !tokens.includes(t)) tokens.push(t);
    }
  }
  if (
    typeof targetData.fcmToken === "string" &&
    targetData.fcmToken &&
    !tokens.includes(targetData.fcmToken)
  ) {
    tokens.push(targetData.fcmToken);
  }

  if (tokens.length === 0) {
    logger.log(`No FCM tokens for user ${targetUid}.`);
    return { success: true, sent: 0 };
  }

  const response = await messaging.sendEachForMulticast({
    tokens,
    notification: { title, body },
    data: data || {},
    android: {
      priority: "high",
      notification: { channelId: "high_importance_channel" },
    },
  });

  logger.log(
    `Admin ${callerUid} notified ${targetUid}: ` +
      `${response.successCount}/${tokens.length} delivered.`,
  );
  return {
    success: true,
    sent: response.successCount,
    failed: response.failureCount,
  };
});

/**
 * Triggers when a new claim is created.
 * Sends a notification to the ITEM OWNER.
 */
export const onNewClaimV2 = onDocumentCreated("claims/{claimId}", async (event) => {
  const snapshot = event.data;
  if (!snapshot) {
    logger.log("No data associated with the event.");
    return;
  }
  const claim = snapshot.data();

  try {
    // 1. Get the item owner's UID from the claim
    const ownerUid = claim.ownerUid;

    // 2. Get the claimer's name to put in the message
    const claimerUid = claim.claimerUid;
    const claimerDoc = await db.collection("users").doc(claimerUid).get();
    const claimerName = claimerDoc.data()?.name || "Someone";

    // 3. Get the owner's user document to find their FCM tokens
    const ownerDoc = await db.collection("users").doc(ownerUid).get();
    const ownerData = ownerDoc.data();

    if (!ownerData?.fcmTokens || ownerData.fcmTokens.length === 0) {
      logger.log("Owner has no FCM tokens.");
      return;
    }
    const tokens: string[] = ownerData.fcmTokens;

    // 4. Send to all of the owner's tokens via the FCM v1 multicast API.
    const response = await messaging.sendEachForMulticast({
      tokens,
      notification: {
        title: "New Claim Request!",
        body: `${claimerName} has sent a claim for one of your items.`,
      },
      data: {
        claimId: event.params.claimId,
        type: "claim",
      },
      android: {
        priority: "high",
        notification: { channelId: "high_importance_channel" },
      },
    });
    logger.log(
      `Sent 'New Claim' to ${ownerUid}: ` +
        `${response.successCount}/${tokens.length} delivered.`,
    );
  } catch (error) {
    logger.error("Error sending 'New Claim' notification:", error);
  }
});

/**
 * Triggers when a new chat message is created.
 * Sends a notification to the RECIPIENT (not the sender).
 */
export const onNewMessageV2 = onDocumentCreated("messages/{messageId}", async (event) => {
  const snapshot = event.data;
  if (!snapshot) {
    logger.log("No data associated with the event.");
    return;
  }
  const message = snapshot.data();

  try {
    const senderUid = message.senderUid;
    const claimId = message.claimId;

    // 1. Get the claim to find out who the two parties are
    const claimDoc = await db.collection("claims").doc(claimId).get();
    const claim = claimDoc.data();
    if (!claim) {
      logger.log("Claim not found.");
      return;
    }

    const ownerUid = claim.ownerUid;
    const claimerUid = claim.claimerUid;

    // 2. Determine who the recipient is
    const recipientUid = senderUid === ownerUid ? claimerUid : ownerUid;

    // 3. Get the sender's name for the message body
    const senderDoc = await db.collection("users").doc(senderUid).get();
    const senderName = senderDoc.data()?.name || "Someone";

    // 4. Get the recipient's FCM tokens
    const recipientDoc = await db.collection("users").doc(recipientUid).get();
    const recipientData = recipientDoc.data();

    if (!recipientData?.fcmTokens || recipientData.fcmTokens.length === 0) {
      logger.log("Recipient has no FCM tokens.");
      return;
    }
    const tokens: string[] = recipientData.fcmTokens;

    // 5. Send via the FCM v1 multicast API.
    const response = await messaging.sendEachForMulticast({
      tokens,
      notification: {
        title: `New Message from ${senderName}`,
        body: message.text,
      },
      data: {
        claimId: String(claimId),
        type: "chat",
      },
      android: {
        priority: "high",
        notification: { channelId: "high_importance_channel" },
      },
    });
    logger.log(
      `Sent 'New Message' to ${recipientUid}: ` +
        `${response.successCount}/${tokens.length} delivered.`,
    );
  } catch (error) {
    logger.error("Error sending 'New Message' notification:", error);
  }
});