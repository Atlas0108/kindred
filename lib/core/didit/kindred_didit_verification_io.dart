import 'dart:io' show Platform;

import 'package:didit_sdk/sdk_flutter.dart';
import 'package:flutter/foundation.dart';

import 'kindred_didit_result.dart';

Future<KindredDiditResult> kindredLaunchDiditVerification({
  required String workflowId,
  required String vendorData,
  String? apiKey,
  String? callbackUrl,
  String? portraitImageBase64,
}) async {
  // Web builds use [kindred_didit_verification_web.dart] instead of this file.
  if (kIsWeb) {
    return const KindredDiditUnsupported('Web is not supported by the native Didit SDK.');
  }
  // [apiKey] / [callbackUrl] are only used on web (Cloud Function + callback).
  if (!Platform.isAndroid && !Platform.isIOS) {
    return const KindredDiditUnsupported(
      'Didit verification is only available on iOS and Android in this app.',
    );
  }

  try {
    final result = await DiditSdk.startVerificationWithWorkflow(
      workflowId,
      vendorData: vendorData,
    );

    switch (result) {
      case VerificationCompleted(:final session):
        final label = switch (session.status) {
          VerificationStatus.approved => 'Approved',
          VerificationStatus.pending => 'Pending review',
          VerificationStatus.declined => 'Declined',
        };
        return KindredDiditSdkCompleted(
          statusLabel: label,
          sessionId: session.sessionId,
        );
      case VerificationCancelled():
        return const KindredDiditSdkCancelled();
      case VerificationFailed(:final error):
        return KindredDiditSdkFailed('${error.type.name}: ${error.message}');
    }
  } on Object catch (e) {
    return KindredDiditSdkFailed(e.toString());
  }
}
