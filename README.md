# RewardX — Firebase production foundation (Android + Web)

This is a security-focused implementation starter, **not a fully launch-ready earning business**. It includes Firebase Auth UI (Google + Email), Firestore client reads, locked-down Firestore rules, callable Cloud Functions for admin stock import and transactional redemption, and an intentionally disabled AdMob SSV endpoint.

## What works after Firebase setup
- Email/password sign-up and sign-in
- Google sign-in (Android and web)
- Live points balance and wallet reads
- Server-side, transactional redemption from private gift-card inventory
- Admin-only inventory screen (visible only to accounts with the `admin` custom claim)
- Idempotent server-side profile initialization
- Admin-only gift-card stock import (custom claim required)

## Not enabled yet
- AdMob reward crediting: `admobSsv` deliberately returns HTTP 503 until ECDSA signature verification and transaction deduplication are implemented and tested. Do not credit points from the client callback.
- Task verification/admin task UI
- Admin dashboard UI and admin bootstrap workflow
- Supplier API integration / automated gift-card purchasing
- Web rewarded-ad provider (Google Mobile Ads Flutter plugin is for mobile platforms; this starter skips ad initialization on web)

## 1. Install tools
Install Flutter, Android Studio, Node.js 20+, Firebase CLI and FlutterFire CLI.

```bash
npm install -g firebase-tools
dart pub global activate flutterfire_cli
firebase login
```

## 2. Create Firebase project
1. Create a project at https://console.firebase.google.com/
2. Add Android app with your exact Android application ID.
3. Add Web app.
4. In Authentication > Sign-in method, enable Email/Password and Google.
5. Create Firestore database.
6. From project root run:

```bash
flutterfire configure
```

This generates `lib/firebase_options.dart` and replaces the placeholder. For Android, add SHA-1 and SHA-256 fingerprints in Firebase project settings and download updated config if the console asks.

## 3. Install packages and run
```bash
flutter pub get
flutter run
```
For web:
```bash
flutter config --enable-web
flutter run -d chrome
```

Google sign-in on web uses Firebase popup; configure authorized domains in Firebase Authentication settings. On Android configure SHA fingerprints and the OAuth client in Firebase/Google Cloud as required by the Firebase setup wizard.

## 4. Deploy Firestore rules and Functions
```bash
firebase use YOUR_PROJECT_ID
cd functions
npm install
npm run build
cd ..
firebase deploy --only firestore:rules,functions
```
Cloud Functions deployment may require the Firebase project to be on the Blaze billing plan. Set budget alerts before deployment.

## 5. Create first admin securely
Do not make a user admin from the Flutter app. Use a trusted local environment with Firebase Admin SDK credentials or a one-time script run by the project owner. Simplest approach:
- Create the admin account by signing up normally.
- In a secure admin machine, use Firebase Admin SDK `setCustomUserClaims(uid, {admin:true})`.
- Sign out/in to refresh the ID token.
- Restrict the service-account key and never commit it to Git.

`addGiftCard` requires the `admin: true` custom claim. Admin inventory fields: `code`, `label`, `productId`, `pointsCost`, `region`. Example product ID: `google_play_inr_100`. Import only legitimate, unused codes acquired from an authorized source.

## 6. Firestore data model
- `users/{uid}`: server-managed `points` integer
- `users/{uid}/wallet/{redemptionId}`: claimed code (read by owner only)
- `giftCards/{cardId}`: private stock; all client access denied
- `redemptions/{id}`: server audit record
- `adTransactions/{transactionId}`: reserved for SSV idempotency ledger

The app calls the trusted `ensureProfile` function after sign-in to create a zero-point profile. Never let clients write points, wallet, inventory or redemptions.

## 7. AdMob rewarded ads — safe rollout
1. Register Android app in AdMob and create a Rewarded ad unit.
2. Use Google's official test ad unit during development; never click your own live ads.
3. Configure the AdMob SSV callback URL to the deployed `admobSsv` HTTPS function.
4. Implement Google ECDSA signature validation against AdMob public keys, validate the configured ad unit and timestamp, and write each `transaction_id` once in a Firestore transaction.
5. Only then enable server-side point crediting. The endpoint in this starter deliberately refuses all callbacks until that verifier exists.
6. For web, integrate a separate provider that explicitly supports rewarded web inventory and server-side callbacks; do not pretend the Android plugin works in browsers.

Official SSV reference: https://developers.google.com/admob/android/ssv

## 8. Gift-card and policy requirements
- Keep supplier agreements/invoices and region restrictions.
- Google Play gift-card redemption is country-specific. Confirm the current India catalog, supplier availability and applicable Google/AdMob/Play policies before advertising the reward.
- Publish clear earning limits, redemption thresholds, expiry/stock rules, privacy policy, terms, support contact and fraud/appeal process.
- Never promise a card unless you have valid stock or a confirmed supplier fulfilment path.
