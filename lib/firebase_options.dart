// Kindred — Firebase Web config.
//
// Google/Firebase **project IDs cannot be renamed**. This app still uses project `gathr-5b405`
// until you create a new Firebase project (e.g. `kindred-xxxxx`) and run:
// `flutterfire configure --project=<new-id> --platforms=web --overwrite-firebase-options`
//
// ## Browser `apiKey` (manual)
// 1. [Google Cloud Console](https://console.cloud.google.com/) → select **gathr-5b405** (or your new project).
// 2. **APIs & Services → Credentials → + CREATE CREDENTIALS → API key**.
// 3. **Edit API key** → Name: e.g. `Kindred Firebase Web`.
// 4. **Application restrictions** → **HTTP referrers** → add `http://localhost:*/*` and `http://127.0.0.1:*/*` (and prod URLs later).
// 5. **API restrictions** → for a prototype choose **Don’t restrict key**, *or* **Restrict** and enable at least:
//    **Identity Toolkit API**, **Cloud Firestore API** (add others if the console suggests for Firebase).
// 6. **Save**, copy the key, paste it below as `apiKey`.
//
// ## Or: FlutterFire CLI
// From the repo root: `flutterfire configure --project=gathr-5b405 --platforms=web --overwrite-firebase-options`
// (after `dart pub global activate flutterfire_cli`). That regenerates this file and usually creates
// a “Browser key (auto created by Firebase)” in Credentials.
//
// `dart pub global activate flutterfire_cli` then `flutterfire configure` also works from a clean clone.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        throw UnsupportedError('DefaultFirebaseOptions are not configured for this platform.');
      default:
        throw UnsupportedError('Unknown platform');
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    // Paste the **Firebase** browser key here (not the Maps key from index.html).
    apiKey: "AIzaSyAvretsjS_CnpmRZXyHuS65LyWHgxoGGeU",
    authDomain: "gathr-5b405.firebaseapp.com",
    projectId: "gathr-5b405",
    storageBucket: "gathr-5b405.firebasestorage.app",
    messagingSenderId: "159475501188",
    appId: "1:159475501188:web:d5df41d3a003acd79b5ad1",
  );
}
