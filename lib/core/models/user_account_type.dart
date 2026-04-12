/// Stored in Firestore as `users/{uid}.accountType`.
enum UserAccountType {
  personal,
  nonprofit,
  business;

  /// Canonical string in `users` documents.
  String get firestoreValue => name;

  static UserAccountType fromFirestore(Object? raw) {
    final s = raw?.toString().trim().toLowerCase() ?? '';
    for (final t in UserAccountType.values) {
      if (t.name == s) return t;
    }
    return UserAccountType.personal;
  }
}
