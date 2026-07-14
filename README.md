# FoundMe

A campus lost-and-found app for **USIM (Universiti Sains Islam Malaysia)** students, built with Flutter and Firebase. Students post items they've lost or found, the app uses Gemini to auto-describe photos and surface likely matches, and the two parties settle the handover through an in-app claim + chat flow. Admins moderate every post before it goes live.

## What it does

**Post a lost or found item.** Snap up to 4 photos, and a Cloud Function (`analyzeItemImage`) runs Gemini over the first one to pre-fill the title, description, category, and tags. Pin the location on a map, pick a category, submit. The post lands in `pending_approval` — it isn't visible to anyone until an admin approves it.

**AI matching.** Right after you post, `findMatchingItems` pulls up to 20 active items of the *opposite* type (you lost → it looks at found) in the same category and asks Gemini which ones actually match, scoring each. Anything scoring above 60 comes back as a suggested match with a reason.

**Claim and chat.** Found your item in the feed? Send a claim with a message. The owner gets a push notification, sees the request in their Claims inbox, and can accept or decline. Accepting locks the item (`acceptedClaimId`) so a second claim can't also be accepted, and auto-declines the rest. Both parties then get a private 1-to-1 chat scoped to that claim.

**Rate each other.** Once a claim is accepted or closed, each side can rate the other once. Ratings are written by a Cloud Function inside a transaction — the client cannot touch `averageRating` or `ratingCount` directly.

**Matric verification.** Before a student can use the app properly, they upload their matric card. `verifyMatricCard` reads it from Storage, asks Gemini whether it's a genuine USIM student ID, extracts the matric number, rejects duplicates already registered to another account, and flips `isVerified` on the user doc. The card image and matric number live in a separate admin-only `verifications` collection; admins fetch a **15-minute signed URL** on demand rather than storing a permanent link to a student ID.

**Guest browsing.** Anonymous sign-in lets visitors read the feed and map, but they can't post, claim, chat, or burn Gemini quota — enforced in both the security rules and the callables.

**Admin console.** A 5-tab dashboard: Overview (charts via `fl_chart`), Approvals (approve/reject pending posts, review matric cards), All Items, Users (ban/unban, backed by `disableUser` which disables the Firebase Auth account), and Reports (user/item abuse reports).

**Housekeeping.** Items auto-expire after 90 days; the feed only queries within that window.

## Screenshots

| Feed | Item detail | Add item (AI fill) |
|---|---|---|
| <img src="docs/screenshots/feed.png" width="220"> | <img src="docs/screenshots/item-detail.png" width="220"> | <img src="docs/screenshots/add-item.png" width="220"> |

| Map view | Claims & chat | Admin console |
|---|---|---|
| <img src="docs/screenshots/map.png" width="220"> | <img src="docs/screenshots/chat.png" width="220"> | <img src="docs/screenshots/admin.png" width="220"> |

> Drop the PNGs into `docs/screenshots/` with the filenames above and they'll render here. Capture them with `flutter screenshot` or your emulator's snapshot button.

## Architecture

```
lib/
  main.dart              AuthGate — the single routing source of truth:
                         signed out → login · guest → home · unverified email → verify
                         · admin → admin console · unverified matric → matric page · else home
  models/                ItemModel, ClaimModel, UserModel, ChatMessage
  models/status.dart     Canonical ClaimStatus / ItemStatus vocabularies + legacy normalizers
  services/              Singleton service layer over Firebase:
                         auth · item · claim · review · report · notification · ai_matching · log
  pages/                 Feed, Map, Add/Edit item, Item detail, Claims inbox, My claims,
                         Chat, Profile, Matric verification, Auth screens, Admin shell
  admin/                 The 5 admin dashboard tabs
  widgets/               Feed card, map picker, rating + report dialogs
functions/src/index.ts   All Cloud Functions (below)
firestore.rules          Firestore security rules
storage.rules            Storage security rules
```

**Firestore collections:** `users`, `items`, `claims`, `messages` (flat, keyed by `claimId`), `reports`, `logs`, `verifications` (admin-read only).

**Item lifecycle:** `pending_approval → active → closed | expired`, or `rejected`.
**Claim lifecycle:** `pending → accepted | declined → closed`. The transitions are enforced as a state machine in `firestore.rules`, not just in the client.

## Cloud Functions

| Function | Trigger | What it does |
|---|---|---|
| `analyzeItemImage` | callable | Gemini → suggested title, description, category, tags for an item photo |
| `findMatchingItems` | callable | Gemini-scored matches against candidate items of the opposite type |
| `verifyMatricCard` | callable | Verifies a USIM matric card, extracts the matric no., sets `isVerified` |
| `getMatricCardUrl` | callable, admin | Mints a 15-minute signed URL to a user's matric card |
| `submitReview` | callable | Transactionally updates a user's rating; enforces one review per side |
| `disableUser` | callable, admin | Bans/unbans a user in Firebase Auth and mirrors the flag onto their doc |
| `sendAdminNotification` | callable, admin | Sends an FCM push (used for post approve/reject) |
| `onNewClaimV2` | `claims/{id}` created | Pushes "New Claim Request!" to the item owner |
| `onNewMessageV2` | `messages/{id}` created | Pushes a chat notification to the other party |
| `migrateLegacyMatricFields` | callable, admin | One-shot migration of matric fields off the user doc |

The Gemini key lives only in the Functions runtime as a Firebase secret (`GEMINI_API_KEY`) — it is never bundled into the app. Dead FCM tokens are pruned from `users/{uid}.fcmTokens` automatically on send failure.

## Security model

- **Guests (anonymous auth)** can read, and nothing else. Blocked at the rules layer *and* inside the paid callables.
- **Users** can escalate nothing: `role`, `disabled`, `isVerified`, and `averageRating`/`ratingCount` are all rejected on self-update via an `affectedKeys` allowlist. Owners can edit their own items but can never flip one to `active` — only an admin can approve.
- **Claims and messages** are readable only by the two parties (or an admin). Chat is append-only.
- **Matric cards** are write-own / read-admin in Storage; the sensitive data sits in `verifications/{uid}`, which no client can write.

## Stack

Flutter (Dart ≥ 3.6) · Firebase Auth (email + Google + anonymous) · Cloud Firestore · Cloud Storage · Cloud Functions (TypeScript, Node) · Firebase Cloud Messaging · Google Maps · Google Gemini (`gemini-2.0-flash-lite-001`) · Riverpod · fl_chart

## Running it

```bash
# App
flutter pub get
flutter run

# Functions
cd functions && npm install
firebase functions:secrets:set GEMINI_API_KEY
firebase deploy --only functions,firestore:rules,storage
```

You'll need your own Firebase project (`flutterfire configure` to regenerate `lib/firebase_options.dart`), a Google Maps API key wired into the Android/iOS manifests, and a Gemini API key set as the secret above. To create the first admin, set `role: "admin"` on your user document in Firestore by hand.

## Notes

`AUDIT.md` in the repo root tracks the security/quality audit of this codebase and the findings that have been fixed.
