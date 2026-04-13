import 'package:flutter/foundation.dart' show debugPrint;

/// Debug trace for hangs. Filter browser / IDE console on `[Public Commons]`.
///
/// Details are stringified so we never pass odd objects into [debugPrint] (and
/// to reduce noise from tooling; heavy logging on Flutter web can still trigger
/// dwds "Cannot send Null" — see https://github.com/flutter/flutter/issues/174437).
void kindredTrace(String step, [Object? detail]) {
  final t = DateTime.now().toIso8601String();
  if (detail == null) {
    debugPrint('[Public Commons $t] $step');
    return;
  }
  try {
    debugPrint('[Public Commons $t] $step | ${detail.toString()}');
  } catch (_) {
    debugPrint('[Public Commons $t] $step | (detail omitted)');
  }
}
