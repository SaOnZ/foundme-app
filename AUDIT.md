# FoundMe — Code & QA Audit (2026-06-06)

Static review of all 45 Dart files (`lib/`), Cloud Functions (`functions/`), and security rules
(`firestore.rules`, `storage.rules`). Findings grouped by area; severity in brackets. File:line refs
are clickable. Runtime tapping was not performed — these are code-traced findings.

---

## CRITICAL

### C1 [Auth] Email verification is never enforced — gate is bypassed
`lib/main.dart:84-113` — `AuthGate` only checks `role` and the matric `isVerified` flag; it never
checks `user.emailVerified`. New email users are routed to Matric Verification, and once the cloud
function flips matric `isVerified`, they reach `/home` with an unverified email. The `/verify` route
is effectively dead. **Fix:** in AuthGate, before the matric check: `if (!isGuest && !user.emailVerified) return VerifyEmailPage();`, and drive off `idTokenChanges()` / `user.reload()` so the flag refreshes.

### C2 [Auth] New-user / guest Firestore-doc race routes users to the wrong screen
`lib/main.dart:91-97` — `userSnap.hasData` is true even when the doc doesn't exist; `data()` is null,
so `role`/`isVerified` default and the user is dumped into MatricVerificationPage. Guests (no doc) get
stuck there forever on any rebuild. **Fix:** branch on `connectionState == waiting` for the spinner,
handle `!snap.data!.exists`, and short-circuit `if (isGuest) return HomePage();`.

### C3 [Items] `_locationController` never disposed (controller leak)
`lib/pages/add_item_page.dart:73-78` — `dispose()` omits `_locationController` (declared line 30).
Each visit leaks a controller + listeners. **Fix:** add `_locationController.dispose();`.

### C4 [Items] `ItemModel.fromDoc` crashes on deleted/empty docs
`lib/models/item.dart:52` + `lib/services/item_service.dart:158-160` — `d.data() as Map<String,dynamic>`
throws when a doc is deleted while being viewed; `getItemStream` has no guard, emitting an uncaught
stream error. **Fix:** `d.data() as Map<String,dynamic>? ?? {}` and `.where((d) => d.exists)`.

### C5 [Claims] Inbox accept/decline swallow all errors (no await/try-catch/feedback)
`lib/pages/claims_inbox_page.dart:156-166` + `lib/services/claim_service.dart:45-49` — fire-and-forget;
rule rejection or offline produces zero feedback. **Fix:** make async, await in try/catch, show SnackBars.

### C6 [Claims] Accept/decline double-submit & approval race; multiple claims can all be accepted
`lib/pages/claims_inbox_page.dart:147-168`, `lib/pages/chat_page.dart:126-157`,
`lib/services/claim_service.dart:45-49` — blind `update` with no transaction/precondition; rapid taps or
two sessions race; sibling pending claims on the same item are not declined. **Fix:** transaction that
only transitions from `pending`; disable buttons in-flight; batch-decline siblings on accept.

### C7 [Admin] Admin authorization is client-side only for most mutations
`lib/admin/manage_users_tab.dart:152,158-170` and item approve/reject/close/delete throughout — only
`disableUser` is a protected callable; everything else writes directly from the client, gated only by
widget `enabled:` flags. If rules don't enforce admin role, any authenticated user can approve/delete/
close any item. **Fix:** enforce admin role + invariants in rules and/or route through callables.

---

## HIGH

### H1 [Auth] Google sign-in errors swallowed → real failures shown as "canceled"
`lib/services/auth_service.dart:293-296`, `lib/pages/login_page.dart:281-291` — any exception returns
null; UI says "canceled or failed". A post-credential Firestore failure leaves the user signed in but
shown an error. **Fix:** rethrow typed errors; distinguish cancel (`googleUser == null`) from failure.

### H2 [Auth] `setState` after await with no `mounted` guard (Google button)
`lib/pages/login_page.dart:265-292` — backgrounding during the account picker disposes the widget →
"setState after dispose". **Fix:** guard both setStates with `mounted`.

### H3 [Auth] Two divergent user-doc schemas + Google users forced into matric
`lib/services/auth_service.dart:237-297` vs `:87-93` — Google path writes `ratingCount`/`averageRating`/
`uid`, email `register()` writes none; Google users never get `isVerified`. **Fix:** centralize user-doc
creation in one helper with a consistent field set.

### H4 [Auth] Login error matching relies on `e.toString().contains('wrong-password')`
`lib/services/auth_service.dart:98-115`, `lib/pages/login_page.dart:104-112` — modern Firebase returns
`invalid-credential`; the tailored branches are dead code. **Fix:** switch on `FirebaseAuthException.code`.

### H5 [Items] Edit writes `'updatedAt': DateTime.now()` instead of a server timestamp
`lib/pages/add_item_page.dart:376` — **Fix:** `FieldValue.serverTimestamp()`.

### H6 [Items] AI tag generation failures swallowed; `tags` assumed String
`lib/pages/add_item_page.dart:153,163-167` — only `print` on error; if cloud fn returns a List,
`.split` throws and is swallowed. **Fix:** SnackBar on error; coerce tags whether String or List.

### H7 [Items] Concurrent AI scans race on shared state; no `mounted` guards
`lib/pages/add_item_page.dart:225,261,112-166` — no `if (_isAiScanning) return;` entry guard; last
finisher wins and clears the flag mid-flight; setStates after await unguarded. **Fix:** entry guard +
`mounted` checks.

### H8 [Items] `whereIn: matchIds` can exceed Firestore's 30-value limit
`lib/pages/add_item_page.dart:351-354` — throws after the item was already created. **Fix:** chunk into
batches of ≤30 or cap matches.

### H9 [Items] `_markResolved` composite-index query has no try/catch
`lib/pages/item_detail_page.dart:79-99` — missing index → uncaught throw → owner can't resolve item.
**Fix:** try/catch with user error; ensure composite index (itemId + status) exists.

### H10 [Chat] Send button double-submit; text cleared without confirming send; no error handling
`lib/pages/chat_page.dart:307-318` — button never disabled; no try/catch; `_c.clear()` after await with
no `mounted`. **Fix:** in-flight flag, try/catch + SnackBar, clear only on success after `mounted`.

### H11 [Chat] Unbounded realtime message stream, no pagination, no auto-scroll
`lib/services/claim_service.dart:79-89`, `lib/pages/chat_page.dart:221-266` — `.snapshots()` with no
`.limit()`. **Fix:** `.limit(50)` desc + reverse, load-older pagination, ScrollController to bottom.

### H12 [Claims] Per-row nested StreamBuilders → N+1 realtime listeners
`lib/pages/claims_inbox_page.dart:93-113`, `lib/pages/my_claims_page.dart:117-127` — up to 2×M live
listeners for essentially static data. **Fix:** one-shot `get()` via FutureBuilder / memoized map /
`whereIn` batch.

### H13 [Claims] Rating eligibility inconsistent; owner can be re-prompted; no persistent "Rate Claimer"
`lib/pages/my_claims_page.dart:90`, `lib/pages/chat_page.dart:158-200` — owner resolve shows for any
`accepted` regardless of `ownerHasReviewed`; rating dialog is one-shot. **Fix:** gate on
`!ownerHasReviewed`; add a persistent Rate-Claimer entry for closed claims.

### H14 [Admin] Dashboard streams entire `items` collection and aggregates on client
`lib/admin/dashboard_overview_tab.dart:26-37` — 4 full `.where().length` scans per rebuild, billed per
doc. **Fix:** Firestore `count()` aggregations or a counter doc maintained by a trigger.

### H15 [Admin] "All Items" / "Users" tabs load entire collections, no pagination
`item_service.dart:162` (`adminGetAllItems`), `auth_service.dart:65` (`adminGetAllUsers`) — unbounded
reads, no search. **Fix:** paginate (`limit` + startAfter), server-side search/filter.

### H16 [Admin] Reports are written but never shown anywhere in the console
`lib/widgets/report_dialog.dart` + `report_service.dart:24` — no tab reads `reports`; the whole abuse-
reporting feature is a dead end. **Fix:** add a Reports tab to view/resolve pending reports.

### H17 [Admin] Approve/Reject: no error handling, no confirmation, no in-flight guard
`lib/admin/approvals_tab.dart:207-221`, `admin_approvals_page.dart:144-165` — silent failure, double-tap
duplicate writes/notifications, Reject has no confirm. **Fix:** await+try/catch+SnackBar, disable while
pending, confirm Reject.

### H18 [Services] FCM notification permission result ignored
`lib/services/notification_service.dart:23` — denied/provisional treated as granted. **Fix:** branch on
`authorizationStatus`; only fetch token/register when authorized/provisional.

### H19 [Services] FCM listeners never cancelled + `init()` called twice → duplicate handlers/leaks
`lib/services/notification_service.dart:32,35,67,76` — listeners not stored/cancelled; `init()` runs in
`main.dart:31` and `home_page.dart:27`. Pushes fire twice, token writes twice. **Fix:** idempotent
`init()` guard, store+cancel subscriptions, remove the HomePage call.

### H20 [Services] Deep-link navigation unvalidated / not auth-gated
`lib/services/notification_service.dart:82-89` — pushes `ChatPage` from unvalidated payload with no
signed-in check. **Fix:** verify `currentUser != null`, validate `claimId`, defer until auth route ready.

### H21 [Rules] Users can write their own `averageRating`/`ratingCount` (reputation fraud)
`firestore.rules:55-62` — self-update freezes role/disabled/isVerified/matric but not the rating fields.
Any user can set `averageRating: 5, ratingCount: 999`. **Fix:** allowlist mutable fields via
`diff(resource.data).affectedKeys().hasOnly([...])` excluding rating fields.

### H22 [Rules] Approved item content is mutable (bait-and-switch)
`firestore.rules:81-85` — owner may edit any field while keeping status `active`. **Fix:** restrict
editable fields; consider forcing re-approval when content changes.

### H23 [Rules] Self-update rule doesn't allowlist fields (escalation surface)
`firestore.rules:55-62` — the `.get(field, default)` pattern leaves non-listed fields writable. **Fix:**
switch to an explicit `affectedKeys().hasOnly([...])` allowlist.

---

## MEDIUM

- **M1 [Auth]** Confirm-password equality checked before form validation and not in the field validator — `register_page.dart:80-85,249-251`. Move equality into `_confirm` validator.
- **M2 [Auth]** Manual empty-field checks bypass trimming; whitespace-only input passes — `login_page.dart:60-68`, `register_page.dart:74-85`. Trim + rely on validators / use email regex.
- **M3 [Auth]** Resend-verification: no try/catch, no `mounted` guard before first setState — `verify_email_page.dart:44-55`.
- **M4 [Auth]** Logout buttons: no loading state / error handling / await guard, repeatable — `verify_email_page.dart:97-100`, `matric_verification_page.dart:174-176`.
- **M5 [Auth]** Password-reset error dumps raw `$e`; also reveals account existence — `forgot_password_page.dart:36-41`. Map `e.code`; show neutral message.
- **M6 [Auth]** Guest→email upgrade partial-failure leaves linked credential but missing doc/verification — `auth_service.dart:203-234`. Report "account created but verification failed" path.
- **M7 [Auth]** AuthGate reads `AuthService.instance.currentUser` instead of `snapshot.data` (stale flashes) — `main.dart:69-71`.
- **M8 [Items]** Feed Lost/Found `type` filter has no UI control — dead filter — `feed_page.dart:37-38,111-115`.
- **M9 [Items]** Re-filter/sort runs inside StreamBuilder on every tick/keystroke, recomputing lowercased blobs — `feed_page.dart:108-134`. Memoize a search blob per item.
- **M10 [Items]** No pagination: `allActiveItems()` (map) and `adminGetAllItems()` unbounded; feed capped at 50 with no load-more — `item_service.dart:135-178`. Map rebuilds full marker Set every tick (`map_view_page.dart:34`).
- **M11 [Items]** Weak validation: no max length on title/desc/tags, no tag count cap, `locationText` free text unrelated to picked coords — `add_item_page.dart:300-318,462-466`.
- **M12 [Items]** Owner sees Resolve on `pending_approval` items (can "resolve" never-approved item) — `item_detail_page.dart:320,337`. Gate Resolve on `status == 'active'`.
- **M13 [Claims]** `closeClaimAndItem` trusts widget-supplied `itemId` with no validation; not transactional — `claim_service.dart:91-97`, `chat_page.dart:164-167`.
- **M14 [Chat]** Messages / `initialMessage` have no max length (1 MB doc limit, no rate limit) — `chat_page.dart:310-315`, `claim_service.dart:69-77`.
- **M15 [Claims]** Status vocabulary inconsistent: `declined` vs `rejected` across model/service/UI; chips mishandle the other value — `chat_page.dart:269-271`, `claim.dart:9`, inbox/my_claims chips. **Define one canonical status enum used everywhere** (also affects item statuses, see M22).
- **M16 [Claims]** `my_posts_page.dart:59-66` uses raw `Image.network` with no `errorBuilder`; empty URLs passed to image widgets; `width:59` typo (`my_claims_page.dart:135`).
- **M17 [Claims]** `createClaim` duplicate-prevention is a non-atomic get-then-set (TOCTOU); composite index required — `claim_service.dart:16-43`. Use deterministic doc id `${itemId}_${uid}` + transaction.
- **M18 [Admin]** Force-close / Re-activate: no confirmation, no error handling — `manage_items_tab.dart:111-113`.
- **M19 [Admin]** `deleteItem` not atomic: doc deleted before photos; storage errors swallowed → orphaned files — `item_service.dart:40-48`. Delete storage first / use a trigger; log failures.
- **M20 [Admin]** Status-dot colors miss `rejected` — `manage_items_tab.dart:44-47`.
- **M21 [Admin]** Per-card FutureBuilder refetches user+verification on every rebuild (N+1) — `approvals_tab.dart:115-125`, `admin_approvals_page.dart:93`. Hoist future into state.
- **M22 [Admin]** Status-string mismatches: dashboard counts `pending_approval` but log coloring checks `pending`/`approved` (dead branches) — `dashboard_overview_tab.dart:33-34,189-200`. Part of M15 canonicalization.
- **M23 [Admin]** Approval/stats StreamBuilders + verification FutureBuilders have no `hasError` branch → permanent spinner on error; missing user/verification doc silently shows 'Unknown' so admin approves an unverified user — `approvals_tab.dart:127-132`, `dashboard_overview_tab.dart:26-29`.
- **M24 [Services]** Profile "Edit Name" dialog `TextEditingController` never disposed — `profile_page.dart:762-804`.
- **M25 [Services]** Profile image upload: `pickImage` not in try/catch (silent failure), no size/type validation — `profile_page.dart:733-760`.
- **M26 [Services]** Logout dialog awaits `logout()` then pops (route may already be torn down); no try/catch — `profile_page.dart:842-866`.
- **M27 [Services]** FCM token not fully invalidated on logout; cross-account token bleed via still-live refresh listener — `auth_service.dart:175-192` + notification_service. Centralize token lifecycle in a `clearToken()`.
- **M28 [Services]** Unsafe cast of dynamic FCM payload `claimId`; non-string throws in fire-and-forget handler — `notification_service.dart:82`. Use `?.toString()` + try/catch.
- **M29 [Backend]** `submitReview` never checks `claim.status` → review-bomb any user by spamming claims — `functions/src/index.ts:60-187`. Require accepted/closed before review.
- **M30 [Backend]** `rating` not type-checked; a string passes `< 0.5 || > 5` and yields `NaN` average — `functions/src/index.ts:78,99-103`. `typeof rating !== 'number' || isNaN(...)`.
- **M31 [Backend]** `migrateLegacyMatricFields` reads entire users collection, sequential writes; permanently callable — `functions/src/index.ts:722-761`. Paginate/batch; remove after migration.
- **M32 [Backend]** Matric-card signed URL expires `01-01-2100` — effectively permanent bearer link to student IDs, bypasses Storage rules — `functions/src/index.ts:512-595`. Short-lived on-demand URLs.
- **M33 [Backend]** Unbounded `imageBase64` + `JSON.parse` of LLM output returned unvalidated; Gemini cost-abuse by any signed-in (incl. anonymous) user — `functions/src/index.ts:482-491,555-564,706-710`. Cap size, validate shape.
- **M34 [Rules]** Claim status whitelist lets owner set `pending` (no state-machine; `closed` not terminal) — `firestore.rules:109-118`.
- **M35 [Rules]** `messages` read rule does a `get()` on the parent claim per message (N+1 billed reads); no pagination — `firestore.rules:34-37,125-135`. Restructure as `claims/{id}/messages` subcollection.

---

## LOW

- **L1 [Auth]** `lib/widgets/auth_choice_sheet.dart` is a 0-byte empty file — implement or delete.
- **L2 [Auth]** `matric_verification_page.dart:20-29,67-77` setStates after await lack `mounted` guards.
- **L3 [Auth]** Debug `print` in production auth/Google/FCM code; user-facing typos ("Guest sign-infailed", "Password do not match", "check you inbox") — `auth_service.dart:294,312`, `login_page.dart:129`, `register_page.dart:81,109`.
- **L4 [Auth]** Google "G" logo loaded from Wikimedia URL per render — bundle as a local asset — `login_page.dart:259-263`.
- **L5 [Auth]** `UserModel.fromDoc` non-null cast throws on missing doc; `adminGetAllUsers` maps without exists check — `user_model.dart:32-33`.
- **L6 [Items]** `withOpacity` deprecated → `withValues(alpha:)` — `feed_item_card.dart:33,90`, `profile_page.dart:654,656` (sweep the codebase).
- **L7 [Items]** `print("MY_TEXT_TOKEN: $token")` logs FCM token; Gemini errors printed — `home_page.dart:43`, `add_item_page.dart:164`. Gate behind `kDebugMode` / remove (also L3).
- **L8 [Items]** MapPickerPage hangs on infinite spinner if location permission denied/`deniedForever` — `map_picker_page.dart:19-26,52-59`. Handle errors + default camera.
- **L9 [Items]** Dead/duplicated `_timeAgo` helper with off-by-one day boundaries — `feed_page.dart:172-189`, `item_detail_page.dart:539-556`.
- **L10 [Items]** `autoExpireOldItems` logs `doc['title']` (re-index, can throw) instead of the read var — `item_service.dart:226-233`.
- **L11 [Claims]** `RatingDialog` pops with no value though caller may expect `true`; not `barrierDismissible:false` during submit — `rating_dialog.dart:34-57`.
- **L12 [Claims]** `RateUserSheet` appears to be dead/parallel code that drops `tags` vs the live `RatingDialog`; hardcodes white bg — `rate_user_sheet.dart`. Remove or consolidate.
- **L13 [Chat]** `ChatPage` dereferences `currentUser!` with no guest/expiry guard — `chat_page.dart:56`.
- **L14 [Admin]** Disable action: no in-flight guard; **no re-enable/unban path** anywhere in console — `manage_users_tab.dart:142-178`.
- **L15 [Admin]** Admin-dashboard logout not wrapped in try/catch — `admin_dashboard_page.dart:14-16`.
- **L16 [Admin]** "View ID" dialog: full-res matric image, no size constraints/placeholder/error — `approvals_tab.dart:180-187`.
- **L17 [Admin]** Legacy duplicate `AdminApprovalsPage` ("Pending Approvaks" typo) reads matric data from the public `users` collection instead of admin-only `verifications` — `admin_approvals_page.dart:13,101`. Delete if unrouted.
- **L18 [Services]** `ai_matching_service.dart` returns `[]` on any failure → "matching failed" indistinguishable from "no matches"; `print` on error — `ai_matching_service.dart:29-32`.
- **L19 [Services]** `log_service.getRecentLogs` untyped stream, no error handling, hard limit 20; pending-server-timestamp rows dropped — `log_service.dart:30-32`.
- **L20 [Backend]** No App Check / rate limiting on any callable; anonymous users can call Gemini functions — `functions/src/index.ts` (all callables).
- **L21 [Backend]** `disableUser`/`verifyMatricCard` use `.update()` (throws if doc missing) after auth/state already changed → inconsistent state — `functions/src/index.ts:229,608`. Use `set(merge:true)`.
- **L22 [Rules]** Profile-picture write allows anonymous guests (no `isUser()`); no object-count limit — `storage.rules:34-37`.
- **L23 [Backend]** Firestore triggers don't validate required fields (claimId/uids) before use — `functions/src/index.ts:318-369,375-439`.

---

## Confirmed OK (not flagged)
- Default-deny catch-alls present in both rule files; no `allow ... if true` anywhere.
- No hardcoded secrets; `GEMINI_API_KEY` is a Firebase secret; AI calls proxied server-side.
- `verifications/{uid}` is client-write-blocked and admin-read-only.
- `submitReview` rating math uses a transaction (correct vs concurrent reviews).
- `functions/lib/index.js` is an up-to-date build of the `.ts` (not stale).
- Most controllers are disposed; feed search debounce, HomePage message subscription, and VerifyEmail timer are correctly cancelled.
- `manage_items_tab` delete and `report_dialog` have proper confirmation + try/catch + mounted guards.
