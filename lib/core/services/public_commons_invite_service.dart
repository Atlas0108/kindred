import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Same region as [functions/index.js] HTTPS callables.
const _functionsRegion = 'us-central1';

/// Sends a join invite email via [sendPublicCommonsInvite] Cloud Function.
Future<void> sendPublicCommonsInviteEmail(String email) async {
  if (FirebaseAuth.instance.currentUser == null) {
    throw StateError('Sign in to send an invite.');
  }
  final trimmed = email.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError('Email is required.');
  }

  final functions = FirebaseFunctions.instanceFor(region: _functionsRegion);
  final callable = functions.httpsCallable('sendPublicCommonsInvite');
  await callable.call(<String, dynamic>{'email': trimmed});
}
