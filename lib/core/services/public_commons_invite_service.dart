import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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

  // Release web uses dart2js; `cloud_functions_web` converts the JS callable
  // result via `dartify()` and can hit `ByteData.getInt64`, which dart2js does
  // not support. The HTTPS callable wire format is plain JSON — call it
  // directly on web and skip that conversion path.
  if (kIsWeb) {
    await _sendPublicCommonsInviteEmailWeb(trimmed);
    return;
  }

  final functions = FirebaseFunctions.instanceFor(region: _functionsRegion);
  final callable = functions.httpsCallable('sendPublicCommonsInvite');
  await callable.call(<String, dynamic>{'email': trimmed});
}

Future<void> _sendPublicCommonsInviteEmailWeb(String email) async {
  final projectId = Firebase.app().options.projectId;
  if (projectId.isEmpty) {
    throw StateError('Firebase is not configured.');
  }
  final user = FirebaseAuth.instance.currentUser!;
  final idToken = await user.getIdToken();
  if (idToken == null || idToken.isEmpty) {
    throw StateError('Sign in again to send an invite.');
  }

  final uri = Uri.parse(
    'https://$_functionsRegion-$projectId.cloudfunctions.net/sendPublicCommonsInvite',
  );

  final headers = <String, String>{
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $idToken',
  };
  try {
    final appCheckToken = await FirebaseAppCheck.instance.getToken();
    if (appCheckToken != null && appCheckToken.isNotEmpty) {
      headers['X-Firebase-AppCheck'] = appCheckToken;
    }
  } on Object {
    // Callable may still succeed without App Check if enforcement is off.
  }

  final response = await http.post(
    uri,
    headers: headers,
    body: jsonEncode(<String, dynamic>{
      'data': <String, dynamic>{'email': email},
    }),
  );

  Object? decoded;
  try {
    decoded = jsonDecode(response.body);
  } on Object {
    decoded = null;
  }

  if (response.statusCode >= 200 && response.statusCode < 300) {
    if (decoded is Map && decoded['error'] != null) {
      _throwCallableHttpError(decoded);
    }
    return;
  }

  if (decoded is Map) {
    _throwCallableHttpError(decoded);
  }

  throw FirebaseFunctionsException(
    code: 'internal',
    message: 'Could not send invite (${response.statusCode}).',
  );
}

void _throwCallableHttpError(Map<dynamic, dynamic> body) {
  final err = body['error'];
  var message = 'Invite request failed.';
  var code = 'unknown';
  if (err is Map) {
    final m = err['message'];
    if (m is String && m.isNotEmpty) message = m;
    final s = err['status'];
    if (s is String && s.isNotEmpty) code = s;
  }
  throw FirebaseFunctionsException(message: message, code: code);
}
