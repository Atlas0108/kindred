/// Internal Public Commons team: sign-in email domain.
const kPublicCommonsAdminEmailDomain = '@publiccommons.app';

/// Whether [email] is allowed to use in-app Admin surfaces (tab, routes).
///
/// Comparison is case-insensitive; surrounding whitespace is ignored.
bool isPublicCommonsAdminEmail(String? email) {
  if (email == null) return false;
  final normalized = email.trim().toLowerCase();
  return normalized.endsWith(kPublicCommonsAdminEmailDomain);
}
