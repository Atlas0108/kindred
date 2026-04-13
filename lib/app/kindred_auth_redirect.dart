import 'package:flutter/foundation.dart';

/// Holds the path (and optional query) a user wanted before sign-in, so we can
/// send them there after auth + profile setup.
class KindredAuthRedirect extends ChangeNotifier {
  String? _pending;

  String? get pending => _pending;

  /// Stores [uri] if it is a safe in-app deep link (path + query only).
  void captureFromUri(Uri uri) {
    final encoded = _encodeIfAllowed(uri);
    if (encoded == null) return;
    _pending = encoded;
    notifyListeners();
  }

  /// Clears any stored target (e.g. on sign-out).
  void clear() {
    if (_pending == null) return;
    _pending = null;
    notifyListeners();
  }

  /// Removes and returns the pending target, or null.
  String? consume() {
    final v = _pending;
    _pending = null;
    if (v != null) notifyListeners();
    return v;
  }

  /// Clears pending if the app has successfully navigated to that destination.
  void clearIfReached(String currentPath) {
    final p = _pending;
    if (p == null) return;
    final pendingPath = p.split('?').first;
    if (pendingPath == currentPath) {
      _pending = null;
      notifyListeners();
    }
  }
}

/// Returns [uri] as `path?query` if allowed, else null.
/// Uses only path and query so full `https://…` URLs from the browser still work.
String? _encodeIfAllowed(Uri uri) {
  final path = uri.path.isEmpty ? '/' : uri.path;
  if (!kindredDeepLinkPathAllowed(path)) return null;
  if (uri.hasQuery) {
    final q = uri.query;
    if (q.contains(RegExp(r'[\r\n]'))) return null;
    return '$path?$q';
  }
  return path;
}

/// Rejects open redirects and unknown routes.
bool kindredDeepLinkPathAllowed(String path) {
  if (!path.startsWith('/') || path.startsWith('//')) return false;
  if (path.contains('..')) return false;

  const exact = <String>{
    '/',
    '/home',
    '/post',
    '/inbox',
    '/profile',
    '/connections',
    '/compose',
    '/post/new/event',
    '/profile/staff',
  };
  if (exact.contains(path)) return true;

  if (path.startsWith('/posts/')) return true;
  if (path.startsWith('/event/')) return true; // /event/:id, /event/:id/edit
  if (path.startsWith('/u/')) return true;
  if (path.startsWith('/chat/')) return true;

  return false;
}

/// Validates a stored or query-provided redirect string for [GoRouter.go].
String? sanitizeRedirectForNavigation(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final t = raw.trim();
  if (!t.startsWith('/') || t.startsWith('//')) return null;
  if (t.contains('..')) return null;

  final q = t.indexOf('?');
  final path = q >= 0 ? t.substring(0, q) : t;
  if (!kindredDeepLinkPathAllowed(path)) return null;

  if (q < 0) {
    return path;
  }
  final query = t.substring(q + 1);
  if (query.contains(RegExp(r'[\r\n]'))) return null;
  return '$path?$query';
}
