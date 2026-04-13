/// Outcome of attempting to open the Didit native verification flow.
sealed class KindredDiditResult {
  const KindredDiditResult();
}

/// User finished the SDK flow (check status; final truth comes from your v3 webhook).
final class KindredDiditSdkCompleted extends KindredDiditResult {
  const KindredDiditSdkCompleted({required this.statusLabel, this.sessionId});

  final String statusLabel;
  final String? sessionId;
}

final class KindredDiditSdkCancelled extends KindredDiditResult {
  const KindredDiditSdkCancelled();
}

final class KindredDiditSdkFailed extends KindredDiditResult {
  const KindredDiditSdkFailed(this.message);

  final String message;
}

/// Web, desktop, or unsupported device — use hosted URL / backend flow instead.
final class KindredDiditUnsupported extends KindredDiditResult {
  const KindredDiditUnsupported(this.reason);

  final String reason;
}
