// Public Commons — Firebase Web config.
//
// Regenerate from Firebase with:
// `flutterfire configure --project=public-commons --platforms=web --overwrite-firebase-options`

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
  apiKey: "AIzaSyANSqtYvBAtaahUiTtTyq-uIC81je_1p5Y",
  authDomain: "public-commons.firebaseapp.com",
  projectId: "public-commons",
  storageBucket: "public-commons.firebasestorage.app",
  messagingSenderId: "473290632975",
  appId: "1:473290632975:web:016cdaad0c6d09ad9e587a",
  measurementId: "G-04NBQ1BK1C"
  );
}
