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

  static void _fillTags(Set<String> tags, String envKey) {
    final raw = dotenv.maybeGet(envKey)?.trim();
    if (raw == null || raw.isEmpty) return;
    tags.clear();
    for (final part in raw.split(',')) {
      final t = part.trim();
      if (t.isNotEmpty) tags.add(t);
    }
  }

  /// Call only when [dotenv.isInitialized] and not in edit mode.
  static void applyHelpOffer({
    required TextEditingController title,
    required TextEditingController body,
    required Set<String> tags,
  }) {
    if (!dotenv.isInitialized) return;
    _fillController(title, 'KINDRED_DEV_HELP_OFFER_TITLE');
    _fillController(body, 'KINDRED_DEV_HELP_OFFER_BODY');
    _fillTags(tags, 'KINDRED_DEV_HELP_OFFER_TAGS');
  }

  static void applyHelpRequest({
    required TextEditingController title,
    required TextEditingController body,
    required Set<String> tags,
  }) {
    if (!dotenv.isInitialized) return;
    _fillController(title, 'KINDRED_DEV_HELP_REQUEST_TITLE');
    _fillController(body, 'KINDRED_DEV_HELP_REQUEST_BODY');
    _fillTags(tags, 'KINDRED_DEV_HELP_REQUEST_TAGS');
  }

  static void applyNewEvent({
    required TextEditingController title,
    required TextEditingController organizer,
    required TextEditingController description,
    required TextEditingController location,
    required Set<String> tags,
  }) {
    if (!dotenv.isInitialized) return;
    _fillController(title, 'KINDRED_DEV_EVENT_TITLE');
    _fillController(organizer, 'KINDRED_DEV_EVENT_ORGANIZER');
    _fillController(description, 'KINDRED_DEV_EVENT_DESCRIPTION');
    _fillController(location, 'KINDRED_DEV_EVENT_LOCATION');
    _fillTags(tags, 'KINDRED_DEV_EVENT_TAGS');
  }
}
