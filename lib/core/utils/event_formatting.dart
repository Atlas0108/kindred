import 'package:intl/intl.dart';

import '../models/community_event.dart';

/// Single line for lists and headers (handles missing [CommunityEvent.endsAt] and multi-day ranges).
String formatEventScheduleLine(CommunityEvent event) {
  final start = event.startsAt.toLocal();
  final end = event.endsAt?.toLocal();
  if (end == null) return DateFormat.yMMMd().add_jm().format(start);
  final sameDay =
      start.year == end.year && start.month == end.month && start.day == end.day;
  if (sameDay) {
    return '${DateFormat.yMMMd().add_jm().format(start)} – ${DateFormat.jm().format(end)}';
  }
  return '${DateFormat.yMMMd().add_jm().format(start)} – ${DateFormat.yMMMd().add_jm().format(end)}';
}
