import 'package:flutter/material.dart';

import '../app/responsive/breakpoints.dart';

/// Sizes a cover image: [narrowAspectRatio] on small screens, fixed height on large.
///
/// Parent should apply [ClipRRect] if rounded corners are needed.
class AdaptivePostCoverFrame extends StatelessWidget {
  const AdaptivePostCoverFrame({
    super.key,
    this.narrowAspectRatio = 4 / 3,
    required this.child,
  });

  final double narrowAspectRatio;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint;
    if (wide) {
      return SizedBox(
        width: double.infinity,
        height: kLargeLayoutPostImageHeight,
        child: child,
      );
    }
    return AspectRatio(
      aspectRatio: narrowAspectRatio,
      child: child,
    );
  }
}
