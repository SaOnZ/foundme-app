import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

// Initialize the Firebase Admin SDK
admin.initializeApp();
const db = admin.firestore();
const messaging = admin.messaging();

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

    // 4. Build the notification payload
    const payload: admin.messaging.MessagingPayload = {
      notification: {
        title: "New Claim Request!",
        body: `${claimerName} has sent a claim for one of your items.`,
        clickAction: "FLUTTER_NOTIFICATION_CLICK",
      },
      data: {
        claimId: event.params.claimId,
        type: "claim",
      },
    };

    // 5. Send the notification to all of the owner's tokens
    await messaging.sendToDevice(tokens, payload);
    logger.log(`Successfully sent 'New Claim' notification to ${ownerUid}`);
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

    // 5. Build the notification payload
    const payload: admin.messaging.MessagingPayload = {
      notification: {
        title: `New Message from ${senderName}`,
        body: message.text, // Use the actual message text
        clickAction: "FLUTTER_NOTIFICATION_CLICK",
      },
      data: {
        claimId: claimId,
        type: "chat",
      },
    };

    // 6. Send the notification
    await messaging.sendToDevice(tokens, payload);
    logger.log(`Successfully sent 'New Message' notification to ${recipientUid}`);
  } catch (error) {
    logger.error("Error sending 'New Message' notification:", error);
  }
});