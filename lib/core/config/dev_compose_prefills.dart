import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Optional `.env` sample copy for compose flows (same idea as [KINDRED_DEV_EMAIL] on sign-in).
class DevComposePrefills {
  DevComposePrefills._();

  static void _fillController(TextEditingController c, String envKey) {
    final v = dotenv.maybeGet(envKey)?.trim();
    if (v != null && v.isNotEmpty) {
      c.text = v;
    }
  }

  /// Call only when [dotenv.isInitialized] and not in edit mode.
  static void applyHelpOffer({
    required TextEditingController title,
    required TextEditingController body,
  }) {
    if (!dotenv.isInitialized) return;
    _fillController(title, 'KINDRED_DEV_HELP_OFFER_TITLE');
    _fillController(body, 'KINDRED_DEV_HELP_OFFER_BODY');
  }

  static void applyHelpRequest({
    required TextEditingController title,
    required TextEditingController body,
  }) {
    if (!dotenv.isInitialized) return;
    _fillController(title, 'KINDRED_DEV_HELP_REQUEST_TITLE');
    _fillController(body, 'KINDRED_DEV_HELP_REQUEST_BODY');
  }

  static void applyNewEvent({
    required TextEditingController title,
    required TextEditingController organizer,
    required TextEditingController description,
  }) {
    if (!dotenv.isInitialized) return;
    _fillController(title, 'KINDRED_DEV_EVENT_TITLE');
    _fillController(organizer, 'KINDRED_DEV_EVENT_ORGANIZER');
    _fillController(description, 'KINDRED_DEV_EVENT_DESCRIPTION');
  }
}
