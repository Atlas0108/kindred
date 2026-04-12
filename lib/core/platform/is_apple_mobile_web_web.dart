// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// True when Flutter Web is running in Mobile Safari / iPad Safari–class browsers,
/// where Firestore IndexedDB persistence is a frequent source of hangs or blank loads.
bool kindredIsAppleMobileWeb() {
  final ua = html.window.navigator.userAgent;
  if (RegExp(r'iPhone|iPad|iPod', caseSensitive: false).hasMatch(ua)) return true;
  // iPadOS requesting desktop site: Mac UA + touch.
  if (RegExp(r'Macintosh', caseSensitive: false).hasMatch(ua) &&
      (html.window.navigator.maxTouchPoints ?? 0) > 2) {
    return true;
  }
  return false;
}
