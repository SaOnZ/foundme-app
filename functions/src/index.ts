import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onCall, HttpsError } from  "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { GoogleGenerativeAI } from "@google/generative-ai";

// Initialize the Firebase Admin SDK
admin.initializeApp();
const db = admin.firestore();
const messaging = admin.messaging();
const storage = admin.storage();

// Gemini API key, supplied via:  firebase functions:secrets:set GEMINI_API_KEY
const geminiKey = defineSecret("GEMINI_API_KEY");
const GEMINI_MODEL = "gemini-2.0-flash-lite-001";

// Pull the first JSON value out of an LLM response that may wrap it in
// ```json blocks or surrounding prose.
function extractJson(raw: string, openChar: "{" | "["): string | null {
  const closeChar = openChar === "{" ? "}" : "]";
  const start = raw.indexOf(openChar);
  const end = raw.lastIndexOf(closeChar);
  if (start === -1 || end === -1 || end < start) return null;
  return raw.substring(start, end + 1);
}

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

// ===================================================================
//  Gemini-backed callable functions.
//  These replace three client-side calls that used to bundle the
//  GEMINI_API_KEY in the APK via .env. The key now lives only in the
//  Functions runtime as a Firebase secret.
// ===================================================================

// analyzeItemImage — reads the photo a user just picked when adding an
// item, returns suggested title / description / category / tag string.
export const analyzeItemImage = onCall(
  { secrets: [geminiKey] },
  async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
      throw new HttpsError("unauthenticated", "You must be logged in.");
    }

    const { imageBase64, validCategories } = request.data as {
      imageBase64?: string;
      validCategories?: string[];
    };
    if (!imageBase64 || typeof imageBase64 !== "string") {
      throw new HttpsError("invalid-argument", "Missing imageBase64.");
    }
    const cats = Array.isArray(validCategories) ? validCategories : [];

    try {
      const genAI = new GoogleGenerativeAI(geminiKey.value());
      const model = genAI.getGenerativeModel({ model: GEMINI_MODEL });

      const prompt =
        "Analyze this lost item image.\n" +
        "Return a single JSON object with these 4 fields:\n" +
        "1. 'title': A short, clear title (e.g., 'Black Leather Wallet').\n" +
        "2. 'description': A helpful description (max 20 words). Focus on " +
        "color, brand, and distinguishing features.\n" +
        `3. 'category': Pick exactly ONE from this list: [${cats.join(", ")}]. ` +
        "If unsure, use 'Others'.\n" +
        "4. 'tags': A single string of 5 comma-separated keywords.\n\n" +
        "IMPORTANT: Return ONLY raw JSON. Do not use Markdown blocks.";

      const result = await model.generateContent([
        prompt,
        { inlineData: { mimeType: "image/jpeg", data: imageBase64 } },
      ]);
      const text = result.response.text();
      const json = extractJson(text, "{");
      if (!json) {
        throw new HttpsError("internal", "Model returned no usable JSON.");
      }
      return JSON.parse(json);
    } catch (e) {
      logger.error("analyzeItemImage failed:", e);
      throw new HttpsError("internal", "Image analysis failed.");
    }
  },
);

// verifyMatricCard — reads the matric card photo the client uploaded to
// matric_cards/{uid}.jpg, asks Gemini to verify it's a valid USIM card
// and extract the matric number, then writes isVerified + matricNumber
// to the user doc using the admin SDK (which bypasses the rule that
// blocks self-set isVerified). Returns success/reason to the client.
export const verifyMatricCard = onCall(
  { secrets: [geminiKey] },
  async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
      throw new HttpsError("unauthenticated", "You must be logged in.");
    }

    const bucket = storage.bucket();
    const filePath = `matric_cards/${callerUid}.jpg`;
    const file = bucket.file(filePath);

    const [exists] = await file.exists();
    if (!exists) {
      throw new HttpsError(
        "not-found",
        "No matric card image found. Please upload first.",
      );
    }

    let imageBase64: string;
    try {
      const [buffer] = await file.download();
      imageBase64 = buffer.toString("base64");
    } catch (e) {
      logger.error("Failed to read matric card image:", e);
      throw new HttpsError("internal", "Could not read uploaded image.");
    }

    let parsed: {
      is_valid_card?: boolean;
      is_usim?: boolean;
      name?: string;
      matric_no?: string;
      reason?: string;
    };
    try {
      const genAI = new GoogleGenerativeAI(geminiKey.value());
      const model = genAI.getGenerativeModel({ model: GEMINI_MODEL });
      const prompt =
        "Analyze this image. It should be a University Student ID " +
        "(Matric Card).\n\n" +
        "1. Is this a valid student ID card?\n" +
        "2. Does it belong to a university named 'USIM' or " +
        "'Universiti Sains Islam Malaysia'?\n" +
        "3. Extract the Student Name and Matric Number.\n\n" +
        "RETURN JSON ONLY:\n" +
        '{"is_valid_card": true, "is_usim": true, ' +
        '"name": "Student Name", "matric_no": "123456", ' +
        '"reason": "Clear USIM logo visible"}';

      const result = await model.generateContent([
        prompt,
        { inlineData: { mimeType: "image/jpeg", data: imageBase64 } },
      ]);
      const text = result.response.text();
      const json = extractJson(text, "{");
      if (!json) {
        throw new HttpsError("internal", "Model returned no usable JSON.");
      }
      parsed = JSON.parse(json);
    } catch (e) {
      logger.error("Matric Gemini call failed:", e);
      throw new HttpsError("internal", "Verification failed.");
    }

    if (!parsed.is_valid_card || !parsed.is_usim || !parsed.matric_no) {
      return {
        success: false,
        reason: parsed.reason || "Could not verify the matric card.",
      };
    }

    // Reject if this matric number is already linked to a different user.
    const dup = await db
      .collection("users")
      .where("matricNumber", "==", parsed.matric_no)
      .limit(1)
      .get();
    if (!dup.empty && dup.docs[0].id !== callerUid) {
      return {
        success: false,
        reason: `Matric ${parsed.matric_no} is already registered to another account.`,
      };
    }

    const [downloadUrl] = await file.getSignedUrl({
      action: "read",
      expires: "01-01-2100",
    });

    await db.collection("users").doc(callerUid).update({
      isVerified: true,
      matricNumber: parsed.matric_no,
      matricName: parsed.name || null,
      matricCardUrl: downloadUrl,
      verificationDate: admin.firestore.FieldValue.serverTimestamp(),
    });

    logger.log(`Matric card verified for ${callerUid}.`);
    return { success: true };
  },
);

// findMatchingItems — given the just-created item, queries Firestore for
// candidate items of the opposite type+category and asks Gemini which
// ones match. Returns the array of matches as { id, score, reason }.
export const findMatchingItems = onCall(
  { secrets: [geminiKey] },
  async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
      throw new HttpsError("unauthenticated", "You must be logged in.");
    }

    const { itemId, imageBase64 } = request.data as {
      itemId?: string;
      imageBase64?: string;
    };
    if (!itemId) {
      throw new HttpsError("invalid-argument", "Missing itemId.");
    }

    const itemDoc = await db.collection("items").doc(itemId).get();
    if (!itemDoc.exists) {
      throw new HttpsError("not-found", "Item not found.");
    }
    const item = itemDoc.data()!;
    if (item.ownerUid !== callerUid) {
      throw new HttpsError(
        "permission-denied",
        "Only the item owner can request matches.",
      );
    }

    const targetType = item.type === "lost" ? "found" : "lost";
    const candidatesSnap = await db
      .collection("items")
      .where("type", "==", targetType)
      .where("category", "==", item.category)
      .where("status", "==", "active")
      .orderBy("postedAt", "desc")
      .limit(20)
      .get();

    if (candidatesSnap.empty) return [];

    const candidateText = candidatesSnap.docs
      .map((d) => {
        const c = d.data();
        const tags = Array.isArray(c.tags) ? c.tags.join(", ") : "";
        return `ID: ${d.id} | Title: ${c.title || ""} | ` +
          `Description: ${c.desc || ""} | Tags: ${tags}`;
      })
      .join("\n");

    const prompt =
      "Act as a matching engine.\n\n" +
      "INPUT ITEM:\n" +
      `Title: ${item.title || ""}\n` +
      `Desc: ${item.desc || ""}\n\n` +
      "CANDIDATE DATABASE:\n" +
      candidateText +
      "\n\nTASK:\n" +
      "Compare the INPUT against EVERY SINGLE ITEM in the CANDIDATE DATABASE.\n\n" +
      "CRITICAL RULES:\n" +
      "1. Do not stop at the first match. Check every candidate.\n" +
      "2. Return ALL matches with a score > 60.\n" +
      "3. If there are 3 matches, return 3 items in the list. If none, " +
      "return an empty list.\n\n" +
      "OUTPUT FORMAT:\n" +
      "Return ONLY a JSON List. Do not write 'Here is the JSON' or use " +
      "markdown blocks.\n" +
      'Example: [{"id": "123", "score": 90, "reason": "Visual match"}]';

    try {
      const genAI = new GoogleGenerativeAI(geminiKey.value());
      const model = genAI.getGenerativeModel({ model: GEMINI_MODEL });

      const parts: Array<
        | string
        | { inlineData: { mimeType: string; data: string } }
      > = [prompt];
      if (imageBase64) {
        parts.push({
          inlineData: { mimeType: "image/jpeg", data: imageBase64 },
        });
      }

      const result = await model.generateContent(parts);
      const text = result.response.text();
      const json = extractJson(text, "[");
      if (!json) return [];
      return JSON.parse(json);
    } catch (e) {
      logger.error("findMatchingItems failed:", e);
      throw new HttpsError("internal", "Match lookup failed.");
    }
  },
);