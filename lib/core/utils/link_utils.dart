bool locationTextLooksLikeHttpUrl(String text) {
  final t = text.trim();
  if (t.isEmpty) return false;
  final u = Uri.tryParse(t);
  return u != null &&
      u.hasScheme &&
      (u.scheme == 'http' || u.scheme == 'https') &&
      u.host.isNotEmpty;
}
